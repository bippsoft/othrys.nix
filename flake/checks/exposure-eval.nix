# flake/checks/exposure-eval.nix
# CORE. What four services expose and persist, read back from evaluated
# hosts. ntfy's own default let anyone who reached the port publish to every
# topic, two services persisted a path systemd replaces with a symlink, and
# three firewall options published an API with no authentication without a
# word. None of that fails evaluation.
{
  hostConfig,
  mkExpectations,
  bootBase,
  functioningHost,
}: let
  host = extra:
    hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
      }
      extra
    ];
  persisted = extra:
    host {
      imports = [
        {
          disko.enableConfig = false;
          fileSystems = {
            "/nix" = {
              device = "/dev/disk/by-label/nix";
              fsType = "btrfs";
            };
            "/persist" = {
              device = "/dev/disk/by-label/persist";
              fsType = "btrfs";
            };
          };
          othrys.system = {
            disko = {
              enable = true;
              device = "/dev/disk/by-id/example";
            };
            impermanence.enable = true;
          };
        }
        extra
      ];
    };

  ntfy = host {othrys.services.ntfy.enable = true;};
  ntfyOpen = host {
    othrys.services.ntfy = {
      enable = true;
      listenAddress = "0.0.0.0";
      defaultAccess = "read-write";
    };
  };
  ntfyProvisioned = host {
    othrys.services.ntfy = {
      enable = true;
      users = ["fleet:$2a$10$hash:user"];
      access = ["fleet:alerts:write-only"];
      tokensFile = "/run/secrets/ntfy-tokens";
    };
  };
  ntfyPersisted = persisted {othrys.services.ntfy.enable = true;};
  scrutinyPersisted = persisted {othrys.services.scrutiny.enable = true;};
  scrutinyOpen = host {
    othrys.services.scrutiny = {
      enable = true;
      openFirewall = true;
    };
  };
  scrutiny = host {othrys.services.scrutiny.enable = true;};
  metricsOpen = host {
    othrys.services.victoriametrics = {
      enable = true;
      openFirewall = true;
    };
  };
  logsOpen = host {
    othrys.services.victorialogs = {
      enable = true;
      openFirewall = true;
    };
  };
  metrics = host {othrys.services.victoriametrics.enable = true;};

  settings = cfg: cfg.services.ntfy-sh.settings;
  podmanUser = (hostConfig [functioningHost {othrys.services.containerization.podman.enable = true;}]).users.users.alice;
  warnsAbout = needle: cfg: builtins.any (w: builtins.match ".*${needle}.*" w != null) cfg.warnings;
  persistedDirs = cfg: map (d: d.directory) cfg.environment.persistence."/persist".directories;
in
  mkExpectations "othrys-eval-exposure" {
    "ntfy denies anonymous clients by default" = (settings ntfy).auth-default-access == "deny-all";
    "ntfy renders no accounts by default" = !((settings ntfy) ? auth-users);
    "ntfy renders provisioned accounts and access rules" = (settings ntfyProvisioned).auth-users == ["fleet:$2a$10$hash:user"] && (settings ntfyProvisioned).auth-access == ["fleet:alerts:write-only"];
    "ntfy reads its tokens from the secret file through the environment" = ntfyProvisioned.systemd.services.ntfy-sh.serviceConfig.EnvironmentFile == ["/run/secrets/ntfy-tokens"];
    "ntfy keeps the tokens out of its settings" = !((settings ntfyProvisioned) ? auth-tokens);
    "ntfy open to the network with anonymous access warns" = warnsAbout "has that access to every topic" ntfyOpen;
    "ntfy on loopback does not warn" = !warnsAbout "every topic" ntfy;
    "ntfy persists the directory systemd creates" = builtins.elem "/var/lib/private/ntfy-sh" (persistedDirs ntfyPersisted) && !builtins.elem "/var/lib/ntfy-sh" (persistedDirs ntfyPersisted);
    "scrutiny persists the directory systemd creates" = builtins.elem "/var/lib/private/scrutiny" (persistedDirs scrutinyPersisted) && !builtins.elem "/var/lib/scrutiny" (persistedDirs scrutinyPersisted);
    "scrutiny with the port open warns about its hub" = warnsAbout "no authentication of its own" scrutinyOpen;
    "scrutiny on loopback does not warn" = !warnsAbout "no authentication" scrutiny;
    "victoriametrics with the port open warns" = warnsAbout "writes and deletes" metricsOpen;
    "victorialogs with the port open warns" = warnsAbout "log ingestion" logsOpen;
    "victoriametrics on loopback does not warn" = !warnsAbout "no authentication" metrics;
    "podman does not put the primary user in the rootful socket's group" = !builtins.elem "podman" podmanUser.extraGroups;
  }
