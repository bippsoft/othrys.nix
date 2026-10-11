# flake/checks/exposure-eval.nix
# CORE. What four services expose and persist, read back from evaluated
# hosts. ntfy's own default let anyone who reached the port publish to every
# topic, two services persisted a path systemd replaces with a symlink, and
# three firewall options published an API with no authentication without a
# word. A publisher with no token pointed at the server that denies it, and a
# collector URL with a password in it, evaluate cleanly too. None of that
# fails evaluation.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
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
            impermanence = {
              enable = true;
              device = "/dev/disk/by-partlabel/root";
            };
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
  # notify beside the local server, which denies a client with no token.
  published = extra:
    host {
      imports = [
        {
          othrys.services.ntfy.enable = true;
          othrys.services.notify.enable = true;
          othrys.services.scrutiny.enable = true;
        }
        extra
      ];
    };
  publishedAnonymous = published {};
  publishedWithToken = published {othrys.services.notify.tokenFile = "/run/secrets/notify-token";};
  publishedWithRule = published {othrys.services.ntfy.access = ["*:alerts:write-only"];};
  publishedOpen = published {othrys.services.ntfy.defaultAccess = "write-only";};
  publishedElsewhere = published {othrys.services.notify.url = "https://ntfy.example.com";};
  refusedNeedle = "so no notification is delivered";
  scrutinyUrls = cfg: cfg.othrys.services.scrutiny.notifyUrls;

  collector = extra:
    host {
      othrys.services.scrutiny.collector =
        {
          enable = true;
          endpoint = "https://scrutiny.example.com";
        }
        // extra;
    };
  collectorPlain = collector {};
  collectorWithPassword = collector {endpoint = "https://alice:example@scrutiny.example.com";};
  collectorWithToken = collector {endpoint = "https://example@scrutiny.example.com";};
  collectorWithFile = collector {environmentFile = "/run/secrets/scrutiny-collector";};
  credentialNeedle = "collector.endpoint carries credentials";

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
    "notify with no token beside the local deny-all server warns" = warnsAbout refusedNeedle publishedAnonymous;
    "notify with a token does not warn" = !warnsAbout refusedNeedle publishedWithToken;
    "an access rule for anonymous clients silences the warning" = !warnsAbout refusedNeedle publishedWithRule;
    "a server that lets anonymous clients write does not warn" = !warnsAbout refusedNeedle publishedOpen;
    "notify pointed at another server does not warn" = !warnsAbout refusedNeedle publishedElsewhere;
    "scrutiny leaves out a notify URL the local server would refuse" = scrutinyUrls publishedAnonymous == [];
    "scrutiny follows notify once anonymous clients may write" = scrutinyUrls publishedWithRule == ["ntfy://127.0.0.1:2586/alerts?scheme=http"];
    "a collector endpoint with a user and password is rejected" = rejectedWith credentialNeedle collectorWithPassword;
    "a collector endpoint with a lone token is rejected" = rejectedWith credentialNeedle collectorWithToken;
    "a collector endpoint without credentials is accepted" = !rejectedWith credentialNeedle collectorPlain;
    "the collector's environment file reaches its unit" = collectorWithFile.systemd.services.scrutiny-collector.serviceConfig.EnvironmentFile == ["/run/secrets/scrutiny-collector"];
    "no environment file is set on the collector without one" = !(collectorPlain.systemd.services.scrutiny-collector.serviceConfig ? EnvironmentFile);
    "ntfy persists the directory systemd creates" = builtins.elem "/var/lib/private/ntfy-sh" (persistedDirs ntfyPersisted) && !builtins.elem "/var/lib/ntfy-sh" (persistedDirs ntfyPersisted);
    "scrutiny persists the directory systemd creates" = builtins.elem "/var/lib/private/scrutiny" (persistedDirs scrutinyPersisted) && !builtins.elem "/var/lib/scrutiny" (persistedDirs scrutinyPersisted);
    "scrutiny with the port open warns about its hub" = warnsAbout "no authentication of its own" scrutinyOpen;
    "scrutiny on loopback does not warn" = !warnsAbout "no authentication" scrutiny;
    "victoriametrics with the port open warns" = warnsAbout "writes and deletes" metricsOpen;
    "victorialogs with the port open warns" = warnsAbout "log ingestion" logsOpen;
    "victoriametrics on loopback does not warn" = !warnsAbout "no authentication" metrics;
    "podman does not put the primary user in the rootful socket's group" = !builtins.elem "podman" podmanUser.extraGroups;
  }
