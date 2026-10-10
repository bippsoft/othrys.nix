# flake/checks/services-eval.nix
# CORE. What the smaller service modules hand upstream and what they refuse,
# read back from evaluated hosts. A blocklist URL, an ACME storage path, a
# repository URL and a provider name are all plain strings upstream, so a
# value that should be refused evaluates cleanly, and an option that is
# declared and never passed on does too.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
}: let
  host = extra: hostConfig [functioningHost extra];

  # Every module set the way a host would set it, on a root that is wiped at
  # boot so the persisted directories can be read back.
  configured = host {
    # impermanence asserts on the disko layout. enableConfig = false keeps
    # disko from emitting filesystems that collide with the fixture's own,
    # so the two volumes impermanence marks as needed for boot are named.
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

    othrys.services = {
      unbound = {
        enable = true;
        interfaces = ["10.0.0.1" "127.0.0.1" "2001:db8:1:2::1" "fe80::1" "0.0.0.0"];
        rpz = [
          {
            name = "blocklist";
            url = "https://blocklist.example.com/rpz.txt";
          }
        ];
      };
      traefik = {
        enable = true;
        dashboard = {
          enable = true;
          insecure = true;
        };
        acme = {
          enable = true;
          email = "alice@example.com";
          dnsProvider = "cloudflare";
          caServer = "https://acme-staging-v02.api.letsencrypt.org/directory";
        };
        environmentFiles = ["/run/secrets/traefik-env"];
      };
      restic = {
        enable = true;
        backups.data = {
          paths = ["/srv/data"];
          repository = "sftp:backup@backup.example.com:/srv/restic";
          environmentFile = "/run/secrets/restic-env";
          timerConfig.OnCalendar = "weekly";
        };
      };
      printing = {
        enable = true;
        listenAddresses = ["*:631"];
        openFirewall = true;
      };
      wireguard = {
        enable = true;
        interfaces.wg0 = {
          privateKeyFile = "/run/secrets/wg0-key";
          ips = ["10.100.0.2/24"];
          mtu = 1280;
          fwMark = "0x6e6978";
          table = "51820";
          peers = [
            {
              publicKey = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=";
              allowedIPs = ["0.0.0.0/0"];
              presharedKeyFile = "/run/secrets/wg0-psk";
            }
          ];
        };
      };
      ddns = {
        enable = true;
        provider = "default@cloudflare.com";
        hostnames = ["home.example.com"];
        credentialsFile = "/run/secrets/ddns";
      };
      headscale = {
        enable = true;
        serverUrl = "https://hs.example.com";
        baseDomain = "tail.example.com";
        nameservers = ["192.0.2.53"];
        port = 8085;
      };
      victoriametrics.enable = true;
      notify.enable = true;
      alerting.enable = true;
    };
  };

  # The same modules with nothing beyond what each needs to evaluate.
  plain = host {
    othrys.services = {
      unbound.enable = true;
      traefik.enable = true;
      printing.enable = true;
      wireguard = {
        enable = true;
        interfaces.wg0 = {
          privateKeyFile = "/run/secrets/wg0-key";
          ips = ["10.100.0.2/24"];
        };
      };
    };
  };

  # One value in each module that has to be refused.
  refused = host {
    othrys.services = {
      unbound = {
        enable = true;
        rpz = [
          {
            name = "blocklist";
            url = "http://blocklist.example.com/rpz.txt";
          }
        ];
      };
      traefik = {
        enable = true;
        acme = {
          enable = true;
          email = "alice@example.com";
          dnsProvider = "cloudflare";
          storage = "/srv/acme.json";
        };
        environmentFiles = ["/run/secrets/traefik-env"];
      };
      restic = {
        enable = true;
        backups.data = {
          paths = ["/srv/data"];
          repository = "rest:https://alice:hunter2@backup.example.com/repo";
          passwordFile = "/run/secrets/restic-password";
        };
      };
    };
  };

  # An enum refuses a value while the option is being read, which aborts the
  # evaluation, so the provider is read under tryEval instead of through an
  # assertion.
  providerOf = provider:
    builtins.tryEval
    (host {
      othrys.services.ddns = {
        enable = true;
        inherit provider;
        hostnames = ["home.example.com"];
        credentialsFile = "/run/secrets/ddns";
      };
    }).othrys.services.ddns.provider;

  unbound = cfg: cfg.services.unbound.settings;
  resolver = cfg: cfg.services.traefik.staticConfigOptions.certificatesResolvers.letsencrypt.acme;
  tcpPorts = cfg: cfg.networking.firewall.allowedTCPPorts;
  wg0 = cfg: cfg.networking.wireguard.interfaces.wg0;
  persisted = cfg: cfg.environment.persistence.${cfg.othrys.system.impermanence.persistRoot}.directories;
  modeOf = directory: cfg: (builtins.head (builtins.filter (d: (d.directory or "") == directory) (persisted cfg))).mode;
  rules = cfg: cfg.environment.etc."vmalert-othrys/rules.yml".source;
  hasInfix = needle: s: builtins.match ".*${needle}.*" s != null;
in
  mkExpectations "othrys-eval-services" {
    "an rpz zone adds the respip module" = (unbound configured).server.module-config == "respip validator iterator";
    "no rpz zone leaves module-config alone" = !((unbound plain).server ? module-config);
    "an https rpz source is accepted" = !rejectedWith "RPZ sources must use https" configured;
    "an http rpz source is rejected" = rejectedWith "RPZ sources must use https" refused;
    "access control is derived from the listen addresses" =
      (unbound configured).server.access-control
      == ["127.0.0.0/8 allow" "::1/128 allow" "10.0.0.0/24 allow" "2001:db8:1:2::/64 allow"];
    "access control without listen addresses is loopback" = (unbound plain).server.access-control == ["127.0.0.0/8 allow" "::1/128 allow"];

    "traefik opens 80 and 443" = builtins.elem 80 (tcpPorts configured) && builtins.elem 443 (tcpPorts configured);
    "traefik never opens 8080, insecure dashboard or not" = !builtins.elem 8080 (tcpPorts configured) && !builtins.elem 8080 (tcpPorts plain);
    "caServer reaches the ACME resolver" = (resolver configured).caServer == "https://acme-staging-v02.api.letsencrypt.org/directory";
    "the default ACME storage is under dataDir" = !rejectedWith "must be under dataDir" configured && (resolver configured).storage == "/var/lib/traefik/acme.json";
    "ACME storage outside dataDir is rejected" = rejectedWith "must be under dataDir" refused;
    "no caServer is written without one" = !((resolver refused) ? caServer);

    "a repository URL with credentials is rejected" = rejectedWith "backups.data.repository carries credentials" refused;
    "a repository URL with a user alone is accepted" = !rejectedWith "carries credentials" configured;
    "a password supplied by the environment file is accepted" = !rejectedWith "backups.data.passwordFile" configured;
    "the backup timer carries the schedule" = configured.systemd.timers."restic-backups-data".timerConfig.OnCalendar == "weekly";
    "the backup unit reads the environment file" = configured.systemd.services."restic-backups-data".serviceConfig.EnvironmentFile == "/run/secrets/restic-env";

    "CUPS listens on loopback by default" = plain.services.printing.listenAddresses == ["localhost:631"] && !plain.services.printing.openFirewall;
    "the CUPS listen addresses are passed on" = configured.services.printing.listenAddresses == ["*:631"];
    "the CUPS firewall switch is passed on" = configured.services.printing.openFirewall && builtins.elem 631 (tcpPorts configured);

    "the wireguard MTU, mark and table are passed on" = (wg0 configured).mtu == 1280 && (wg0 configured).fwMark == "0x6e6978" && (wg0 configured).table == "51820";
    "the preshared key file reaches the peer" = (builtins.head (wg0 configured).peers).presharedKeyFile == "/run/secrets/wg0-psk";
    "wireguard keeps upstream's defaults when unset" = (wg0 plain).mtu == null && (wg0 plain).fwMark == null && (wg0 plain).table == "main";

    "a registered provider name is accepted" = configured.services.inadyn.settings.provider ? "default@cloudflare.com";
    "the bare service name is accepted" = (providerOf "cloudflare.com").success;
    "a misspelt provider is refused" = !(providerOf "cloudflare.con").success;

    "the headscale state directory is persisted as 0750" = modeOf "/var/lib/headscale" configured == "0750";

    "the alert rules pass through vmalert at build time" = (rules configured).name == "vmalert-othrys-rules.yml" && hasInfix "-dryRun" (rules configured).buildCommand;
  }
