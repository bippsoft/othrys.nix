# flake/checks/headscale-eval.nix
# CORE. What the headscale module renders and refuses, read back from
# evaluated hosts. The VM test registers a client; it says nothing about the
# policy, the OIDC lists, the port clashes or the base-domain rule, none of
# which fails on its own.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
}: let
  host = extra:
    hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
        othrys.services.headscale = {
          enable = true;
          serverUrl = "https://hs.example.com";
          baseDomain = "tail.example.com";
          nameservers = ["192.0.2.53"];
        };
      }
      extra
    ];

  settings = cfg: cfg.services.headscale.settings;
  warnsAbout = needle: cfg: builtins.any (w: builtins.match ".*${needle}.*" w != null) cfg.warnings;

  plain = host {};
  oidcOpen = host {
    othrys.services.headscale.oidc = {
      enable = true;
      issuer = "https://auth.example.com";
      clientId = "headscale";
      clientSecretFile = "/run/secrets/headscale-oidc";
    };
  };
  oidcClosed = host {
    othrys.services.headscale.oidc = {
      enable = true;
      issuer = "https://auth.example.com";
      clientId = "headscale";
      clientSecretFile = "/run/secrets/headscale-oidc";
      allowedDomains = ["example.com"];
      allowedGroups = ["tailnet"];
    };
  };
  withPolicy = host {
    othrys.services.headscale.policy = {
      acls = [
        {
          action = "accept";
          src = ["*"];
          dst = ["*:*"];
        }
      ];
    };
  };
  policyFile = host {othrys.services.headscale.policy = ./headscale-eval.nix;};
  sharedLetters = host ({lib, ...}: {
    othrys.services.headscale.serverUrl = lib.mkForce "https://hs.notexample.com";
    othrys.services.headscale.baseDomain = lib.mkForce "example.com";
  });
  suffix = host ({lib, ...}: {
    othrys.services.headscale.serverUrl = lib.mkForce "https://hs.example.com:443/";
    othrys.services.headscale.baseDomain = lib.mkForce "example.com";
  });
  noOverride = host ({lib, ...}: {
    othrys.services.headscale.nameservers = lib.mkForce [];
    othrys.services.headscale.settings.dns.override_local_dns = false;
  });
  withScrutiny = host {othrys.services.scrutiny.enable = true;};
  withCrowdsec = host {
    othrys.services.security.crowdsec = {
      enable = true;
      collections = [];
    };
  };
  withDocs = host {
    othrys.services.docs.enable = true;
    othrys.services.headscale.ui = {
      enable = true;
      cookieSecretFile = "/run/secrets/headplane-cookie";
    };
  };
  persisted = host {
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
  };
  stateEntry = builtins.head (builtins.filter (d: (d.directory or "") == "/var/lib/headscale") persisted.environment.persistence."/persist".directories);
in
  mkExpectations "othrys-eval-headscale" {
    "no policy is rendered by default" = (settings plain).policy.path == null;
    "a policy given as attributes is written out and named" = (settings withPolicy).policy.mode == "file" && builtins.match ".*headscale-policy\\.json" (settings withPolicy).policy.path != null;
    "a policy given as a path is used as given" = builtins.match ".*headscale-eval\\.nix" (settings policyFile).policy.path != null;
    "OIDC with no list warns that every account can register" = warnsAbout "every account at" oidcOpen;
    "OIDC with a list does not warn" = !warnsAbout "every account at" oidcClosed;
    "the OIDC domain and group lists are rendered" = (settings oidcClosed).oidc.allowed_domains == ["example.com"] && (settings oidcClosed).oidc.allowed_groups == ["tailnet"];
    "an empty OIDC list stays at upstream's empty default" = (settings oidcClosed).oidc.allowed_users == [];
    "a base domain that shares letters with the host is accepted" = !rejectedWith "baseDomain" sharedLetters;
    "a base domain that is a suffix of the host is rejected" = rejectedWith "suffix of it" suffix;
    "nameservers are not required when local DNS is not overridden" = !rejectedWith "nameservers" noOverride;
    "the scrutiny port clash is rejected" = rejectedWith "scrutiny.port" withScrutiny;
    "the crowdsec port clash is rejected" = rejectedWith "CrowdSec local API" withCrowdsec;
    "the docs port clash is rejected" = rejectedWith "docs.port" withDocs;
    "the state directory is persisted with upstream's mode" = stateEntry.mode == "0750";
  }
