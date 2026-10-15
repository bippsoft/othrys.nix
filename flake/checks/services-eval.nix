# flake/checks/services-eval.nix
# CORE. What the smaller service modules hand upstream and what they refuse,
# read back from evaluated hosts. A blocklist URL, an ACME storage path, a
# repository URL and a provider name are all plain strings upstream, so a
# value that should be refused evaluates cleanly, and an option that is
# declared and never passed on does too. Ollama's backend follows the GPU,
# since a CUDA build on a host without an NVIDIA card evaluates and runs on
# the CPU.
{
  hostConfig,
  impermanenceModules,
  mkExpectations,
  rejectedWith,
  functioningHost,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;
  host = extra: hostConfig [functioningHost extra];

  # Every module set the way a host would set it, on a root that is wiped at
  # boot so the persisted directories can be read back.
  configured = host {
    imports = [impermanenceModules];
    # No disk layout is imported, so the wipe is given its device by hand and
    # the two volumes impermanence marks as needed for boot are named.
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
          user = "backup";
          backupPrepareCommand = "systemctl stop example.service";
          backupCleanupCommand = "systemctl start example.service";
        };
        # An sftp URL names a login and a port, and no secret.
        backups.sftp = {
          paths = ["/srv/data"];
          repository = "sftp://backup@backup.example.com:2222//srv/restic";
          passwordFile = "/run/secrets/restic-password";
          runCheck = false;
        };
        backups.fromFile = {
          paths = ["/srv/data"];
          repositoryFile = "/run/secrets/restic-repository";
          passwordFile = "/run/secrets/restic-password";
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
          allowedIPsAsRoutes = false;
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
        backups.token = {
          paths = ["/srv/data"];
          repository = "rest:https://example@backup.example.com/repo";
          passwordFile = "/run/secrets/restic-password";
        };
        backups.query = {
          paths = ["/srv/data"];
          repository = "rest:https://backup.example.com/repo?access_token=example";
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

  ollamaOn = {othrys.apps.ai.ollama.enable = true;};
  ollamaNvidia = host {
    imports = [ollamaOn];
    othrys.system.nix.allowUnfree = true;
    othrys.hardware.nvidia.enable = true;
  };
  ollamaGraphics = host {
    imports = [ollamaOn];
    hardware.graphics.enable = true;
  };
  ollamaHeadless = host ollamaOn;
  backendOf = cfg: cfg.othrys.apps.ai.ollama.acceleration;

  unbound = cfg: cfg.services.unbound.settings;
  resolver = cfg: cfg.services.traefik.staticConfigOptions.certificatesResolvers.letsencrypt.acme;
  tcpPorts = cfg: cfg.networking.firewall.allowedTCPPorts;
  wg0 = cfg: cfg.networking.wireguard.interfaces.wg0;
  backupUnit = name: cfg: cfg.systemd.services."restic-backups-${name}";
  lastStep = name: cfg: toString (lib.last (backupUnit name cfg).serviceConfig.ExecStart);
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
    "the insecure dashboard beside headscale on another port is accepted" = !rejectedWith "dashboard.insecure serves the dashboard" configured;
    "traefik never opens 8080, insecure dashboard or not" = !builtins.elem 8080 (tcpPorts configured) && !builtins.elem 8080 (tcpPorts plain);
    "caServer reaches the ACME resolver" = (resolver configured).caServer == "https://acme-staging-v02.api.letsencrypt.org/directory";
    "the default ACME storage is under dataDir" = !rejectedWith "must be under dataDir" configured && (resolver configured).storage == "/var/lib/traefik/acme.json";
    "ACME storage outside dataDir is rejected" = rejectedWith "must be under dataDir" refused;
    "no caServer is written without one" = !((resolver refused) ? caServer);

    "a repository URL with credentials is rejected" = rejectedWith "backups.data.repository carries credentials" refused;
    "a repository URL with a user alone is accepted" = !rejectedWith "carries credentials" configured;
    "a password supplied by the environment file is accepted" = !rejectedWith "backups.data.passwordFile" configured;
    "a repository URL with a lone token before the host is rejected" = rejectedWith "backups.token.repository carries credentials" refused;
    "a repository URL with a token in its query is rejected" = rejectedWith "backups.query.repository carries credentials" refused;
    "an sftp URL with a login and a port is accepted" = !rejectedWith "backups.sftp.repository carries credentials" configured;
    "the repository file reaches the unit and no repository does" = (backupUnit "fromFile" configured).environment.RESTIC_REPOSITORY_FILE == "/run/secrets/restic-repository" && (backupUnit "fromFile" configured).environment.RESTIC_REPOSITORY == null;
    "the backup runs as the user it names" = (backupUnit "data" configured).serviceConfig.User == "backup";
    "the prepare command runs before the backup" = hasInfix "backupPrepareCommand" (backupUnit "data" configured).preStart;
    "the cleanup command runs after it" = hasInfix "backupCleanupCommand" (backupUnit "data" configured).postStop;
    "the repository check is the last step and a step of its own" = lib.hasSuffix "restic-backups-data-check" (lastStep "data" configured) && !builtins.any (hasInfix " check ") (backupUnit "data" configured).serviceConfig.ExecStart;
    "runCheck = false leaves the check step out" = !lib.hasSuffix "-check" (lastStep "sftp" configured);
    "a failed backup unit is reported by the restic failure unit" = (backupUnit "data" configured).onFailure == ["restic-notify-failure@%n.service"];
    "the failure unit tells a failed check from a failed backup" = let
      unit = configured.systemd.services."restic-notify-failure@".serviceConfig;
    in
      lib.hasSuffix "restic-notify-failure %i" unit.ExecStart && unit.DynamicUser;
    "the backup timer carries the schedule" = configured.systemd.timers."restic-backups-data".timerConfig.OnCalendar == "weekly";
    "the backup unit reads the environment file" = configured.systemd.services."restic-backups-data".serviceConfig.EnvironmentFile == "/run/secrets/restic-env";

    "CUPS listens on loopback by default" = plain.services.printing.listenAddresses == ["localhost:631"] && !plain.services.printing.openFirewall;
    "the CUPS listen addresses are passed on" = configured.services.printing.listenAddresses == ["*:631"];
    "the CUPS firewall switch is passed on" = configured.services.printing.openFirewall && builtins.elem 631 (tcpPorts configured);

    "allowedIPs install no routes when the host says so" = !(wg0 configured).allowedIPsAsRoutes;
    "allowedIPs install routes by default" = (wg0 plain).allowedIPsAsRoutes;
    "the wireguard MTU, mark and table are passed on" = (wg0 configured).mtu == 1280 && (wg0 configured).fwMark == "0x6e6978" && (wg0 configured).table == "51820";
    "the preshared key file reaches the peer" = (builtins.head (wg0 configured).peers).presharedKeyFile == "/run/secrets/wg0-psk";
    "wireguard keeps upstream's defaults when unset" = (wg0 plain).mtu == null && (wg0 plain).fwMark == null && (wg0 plain).table == "main";

    "a registered provider name is accepted" = configured.services.inadyn.settings.provider ? "default@cloudflare.com";
    "the bare service name is accepted" = (providerOf "cloudflare.com").success;
    "a misspelt provider is refused" = !(providerOf "cloudflare.con").success;

    "the headscale state directory is persisted as 0750" = modeOf "/var/lib/headscale" configured == "0750";

    "the alert rules pass through vmalert at build time" = (rules configured).name == "vmalert-othrys-rules.yml" && hasInfix "-dryRun" (rules configured).buildCommand;

    "Ollama takes CUDA on an NVIDIA host" = backendOf ollamaNvidia == "cuda";
    "Ollama takes Vulkan on another host with graphics" = backendOf ollamaGraphics == "vulkan" && !ollamaGraphics.othrys.hardware.nvidia.enable;
    "Ollama takes the CPU build on a host without graphics" = backendOf ollamaHeadless == "cpu" && !ollamaHeadless.hardware.graphics.enable;
  }
