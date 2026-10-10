# flake/checks/service-state-eval.nix
# CORE. What the service modules persist under impermanence, read back from an
# evaluated host. Each module declares its own state at the path the service
# writes to, and the two shapes that get this wrong, a plain directory where a
# DynamicUser unit expects systemd's /var/lib/private symlink, and no entry at
# all, both evaluate cleanly and only show on a rebooted host. The paths and
# the owners are pinned here against what the upstream units declare.
{
  hostConfig,
  mkExpectations,
  bootBase,
}: let
  services = {
    # The lowest each module needs to evaluate. kea refuses to start with no
    # interface, alerting wants a datasource and a delivery path, crowdsec's
    # bouncer wants nftables, and an empty collection list keeps the engine
    # from naming hub content the fixture never fetches.
    networking.nftables.enable = true;
    othrys.services = {
      kea = {
        enable = true;
        dhcp4.interfaces = ["lan0"];
      };
      security.fail2ban.enable = true;
      security.crowdsec = {
        enable = true;
        collections = [];
      };
      suricata.enable = true;
      unbound = {
        enable = true;
        rpz = [
          {
            name = "hagezi";
            url = "https://example.com/pro.txt";
          }
        ];
      };
      victorialogs.enable = true;
      monitoring.enable = true;
      notify = {
        enable = true;
        url = "https://ntfy.example.com";
      };
      alerting.enable = true;
    };
  };

  host = extra:
    hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
      }
      services
      extra
    ];

  # impermanence asserts on the disko layout. enableConfig = false keeps
  # disko from emitting filesystems that collide with the fixture's own, so
  # the two volumes impermanence marks as needed for boot are named here.
  impermanent = {
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

  wiped = host impermanent;
  kept = host {};
  externalNotifier = host {
    imports = [impermanent];
    othrys.services.alerting.notifierUrls = ["http://alertmanager.example.com:9093"];
  };

  root = wiped.othrys.system.impermanence.persistRoot;
  entriesOf = cfg: cfg.environment.persistence.${root}.directories;
  pathOf = entry: entry.dirPath or entry.directory;
  persisted = path: cfg: builtins.any (entry: pathOf entry == path) (entriesOf cfg);
  ownedBy = path: user: mode: cfg:
    builtins.any (entry: pathOf entry == path && entry.user == user && entry.mode == mode) (entriesOf cfg);

  rpzZones = wiped.services.unbound.settings.rpz;
in
  mkExpectations "othrys-eval-service-state" {
    "with impermanence off no service declares the persist root" = !(kept.environment.persistence ? ${root});
    "the impermanent host evaluates" = wiped.system.build.toplevel.drvPath != null;

    "kea persists its DynamicUser state directory under /var/lib/private" = ownedBy "/var/lib/private/kea" "root" "0700" wiped;
    "kea does not bind-mount over the /var/lib/kea symlink" = !(persisted "/var/lib/kea" wiped);

    "fail2ban persists its ban database at upstream's mode" = ownedBy "/var/lib/fail2ban" "root" "0750" wiped;

    "crowdsec persists its state directory for its static account" = ownedBy "/var/lib/crowdsec" "crowdsec" "0755" wiped;
    "crowdsec persists the bouncer's API key beside the engine state" = ownedBy "/var/lib/crowdsec-firewall-bouncer-register" "crowdsec" "0755" wiped;

    "suricata persists its rules for the run-as account" = ownedBy "/var/lib/suricata" "suricata" "0755" wiped;

    "unbound persists its state directory for its own account" = ownedBy "/var/lib/unbound" "unbound" "0755" wiped;
    "every RPZ zone names a zonefile so the fetched zone lands on disk" = builtins.all (zone: zone ? zonefile) rpzZones && rpzZones != [];

    "victorialogs persists its log store under /var/lib/private" = ownedBy "/var/lib/private/victorialogs" "root" "0700" wiped;
    "victorialogs persists the journal-upload cursor under /var/lib/private" = ownedBy "/var/lib/private/systemd/journal-upload" "root" "0700" wiped;

    "prometheus persists the directory its stateDir names for its own account" = ownedBy "/var/lib/${wiped.services.prometheus.stateDir}" "prometheus" "0700" wiped;

    "alertmanager persists its DynamicUser state directory under /var/lib/private" = ownedBy "/var/lib/private/alertmanager" "root" "0700" wiped;
    "a host with its own notifiers runs no alertmanager and persists none" = !externalNotifier.services.prometheus.alertmanager.enable && !(persisted "/var/lib/private/alertmanager" externalNotifier);
  }
