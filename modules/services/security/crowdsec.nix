# modules/services/security/crowdsec.nix
# CrowdSec security engine and nftables firewall bouncer, both from nixpkgs
#
# The engine parses logs and decides, while the bouncer enforces those
# decisions in nftables. registerBouncer wires the two automatically, so no
# manual `cscli bouncers add` / API key is needed for the local setup.
#
# Central-console enrollment (crowd-sourced blocklists) is a one-time runtime
# step, `cscli console enroll <key>` with a key from your secrets provider,
# and is intentionally left to the fleet.
#
# The nixpkgs module was rewritten in October 2026 and now boots a fresh
# host on its own. What remains here keeps the state directory of hosts that
# ran the old module, restores `openFirewall`, which upstream dropped, and
# orders the setup unit after a local resolver. The `crowdsec-test` check in
# flake/checks/crowdsec.nix boots a fresh VM and is the regression guard.
#
# On a router the bouncer's own chains hook input only, so a banned address
# could still be forwarded to the LAN. This module adds a forward hook to the
# bouncer's tables there. What the engine watches is the sshd journal, plus
# Traefik's access log when that module is on. Tailscale SSH has no CrowdSec
# parser, so its logins are not watched.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.security.crowdsec;
  routerEnabled = config.othrys.services.router.enable;
  traefikEnabled = config.othrys.services.traefik.enable;
  bouncer = config.services.crowdsec-firewall-bouncer.settings;
  forwardHook = cfg.firewallBouncer.enable && routerEnabled && bouncer.mode == "nftables";
  lapiUri = config.services.crowdsec.settings.config.api.server.listen_uri;

  # A chain in the bouncer's own table, where its set lives, hooked on forward
  # just ahead of the router's chain. mkAfter keeps it behind the set
  # declaration upstream renders, which nft needs to come first.
  forwardChain = set: family: ''
    chain crowdsec-forward {
      type filter hook forward priority filter - 1; policy accept;
      ${family} saddr @${set} drop
    }
  '';
in {
  # ANCHOR: crowdsec-options
  options.othrys.services.security.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec security engine + firewall bouncer";

    collections = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["crowdsecurity/linux" "crowdsecurity/sshd"];
      description = "CrowdSec hub collections to install (bundle parsers + scenarios).";
    };

    acquisitions = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [
        {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
          labels.type = "syslog";
        }
      ];
      description = ''
        Log sources CrowdSec parses (see the CrowdSec data-sources docs).
        Setting this replaces the curated default outright, including the sshd
        journal source, so list every source the host should watch rather than
        only the ones being added. Traefik's access log is added beside this
        list on a host with `othrys.services.traefik`, and the module turns
        that log on. Tailscale SSH has no CrowdSec parser and is not watched.
      '';
    };

    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run `cscli hub update` daily.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the CrowdSec LAPI port in the firewall.";
    };

    firewallBouncer.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the nftables firewall bouncer that enforces CrowdSec decisions (auto-registered with the local engine).";
    };
  };
  # ANCHOR_END: crowdsec-options

  config = lib.mkIf cfg.enable {
    # The engine reads the sshd journal, and a login through Tailscale SSH
    # never reaches sshd. tailscaled answers it, and CrowdSec ships no
    # parser for what tailscaled logs.
    warnings = lib.optional (config.othrys.services.tailscale.enable && config.othrys.services.tailscale.ssh) "othrys.services.security.crowdsec: othrys.services.tailscale.ssh is on, and CrowdSec has no parser for Tailscale SSH, so those logins are not watched. Access through it is limited by the tailnet's ACLs alone.";

    services.crowdsec = {
      enable = true;
      autoUpdateService = cfg.autoUpdate;
      hub.collections = cfg.collections ++ lib.optional traefikEnabled "crowdsecurity/traefik";
      settings.acquisitions =
        cfg.acquisitions
        ++ lib.optional traefikEnabled {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=traefik.service"];
          labels.type = "traefik";
        };

      # The rewritten nixpkgs module keeps its data in /var/lib/crowdsec/data,
      # and the one before it used /var/lib/crowdsec/state. Pinning the old
      # path keeps the decision database, the hub and the machine credentials
      # of a host that ran it, and the hub, the database and the credentials
      # all derive their paths from this one.
      settings.config.config_paths.data_dir = "/var/lib/crowdsec/state";
    };

    # The engine serves its Local API on loopback unless listen_uri says
    # otherwise, so this matters only beside a changed listen_uri. nixpkgs
    # dropped its own openFirewall in the rewrite.
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (lib.toInt (lib.last (lib.splitString ":" lapiUri)))
    ];

    services.crowdsec-firewall-bouncer = lib.mkIf cfg.firewallBouncer.enable {
      enable = true;
      # Register with the locally running engine (no manual API key needed).
      registerBouncer.enable = true;
    };

    # /var/lib/crowdsec holds the hub, the decision database and the machine
    # credentials minted on first start. The bouncer's API key lives in
    # /var/lib/crowdsec-firewall-bouncer-register, and the two go together.
    # The engine database records the bouncer as registered, and when the
    # key file is gone the register unit deletes that record and registers
    # the bouncer again under a new key on every boot.
    othrys.internal.persist."services.security.crowdsec" = {
      directories =
        [
          {
            directory = "/var/lib/crowdsec";
            user = config.services.crowdsec.user;
            group = config.services.crowdsec.group;
            mode = "0755";
          }
        ]
        ++ lib.optional cfg.firewallBouncer.enable {
          directory = "/var/lib/crowdsec-firewall-bouncer-register";
          user = config.services.crowdsec.user;
          group = config.services.crowdsec.group;
          mode = "0755";
        };
    };

    networking.nftables.tables = lib.mkIf forwardHook {
      ${bouncer.nftables.ipv4.table}.content = lib.mkAfter (forwardChain bouncer.blacklists_ipv4 "ip");
      ${bouncer.nftables.ipv6.table}.content = lib.mkAfter (forwardChain bouncer.blacklists_ipv6 "ip6");
    };

    # The traefik parser reads access-log lines, which Traefik writes only
    # when asked. JSON to stdout lands in the journal the acquisition reads.
    services.traefik.staticConfigOptions.accessLog = lib.mkIf traefikEnabled (lib.mkDefault {format = "json";});

    # crowdsec-setup fetches the hub index, and the engine waits on it.
    # `After=network-online.target` covers boot and nothing else. During a
    # switch on a host that resolves through its own unbound, systemd restarts
    # both in one transaction with no order between them, and the fetch lands
    # while the resolver is down. Restart transactions honour After=, so this
    # makes the resolver come back first.
    systemd.services.crowdsec-setup.after = lib.optional config.othrys.services.unbound.enable "unbound.service";
  };
}
