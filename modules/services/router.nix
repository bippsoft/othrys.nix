# modules/services/router.nix
# L3 router firewall + NAT (nftables). Generates a default-drop `inet` filter
# (input/forward) and an `ip` NAT masquerade from WAN/LAN interface options, with
# an optional NFQUEUE hook that hands forwarded traffic to Suricata (pair with
# othrys.services.suricata mode = "nfqueue").
#
# Thin by design, since interface names and subnets are identity and come from the
# fleet host. Anything the generated ruleset doesn't cover goes through the
# raw extraInputRules / extraForwardRules / extraNat passthroughs.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.router;

  hasLan = cfg.lan.interfaces != [];
  # nftables interface set literal, e.g. { "br-lan", "eth1" }
  lanSet = "{ " + lib.concatMapStringsSep ", " (i: "\"${i}\"") cfg.lan.interfaces + " }";

  multiQueue = cfg.suricata.queues > 1;
  queueRange =
    if multiQueue
    then "0-${toString (cfg.suricata.queues - 1)}"
    else "0";
  # Verb for allowed forwarded traffic, either handing it to Suricata via
  # NFQUEUE when the IPS hook is on, otherwise a plain accept.
  #
  # `bypass` accepts packets when NO process is bound to the queue, so a dead or
  # stopped Suricata does not take the link down. It is set unconditionally and
  # is a separate mechanism from othrys.services.suricata.nfqueue.failOpen, which
  # covers a running Suricata whose queue is full. The consequence is that a dead
  # IPS means uninspected traffic rather than blocked traffic.
  fwdVerb =
    if cfg.suricata.enable
    then "queue num ${queueRange} ${lib.optionalString multiQueue "fanout,"}bypass"
    else "accept";
in {
  # ANCHOR: router-options
  options.othrys.services.router = {
    enable = lib.mkEnableOption "L3 router firewall + NAT (nftables)";

    wan.interface = lib.mkOption {
      type = lib.types.str;
      example = "enp1s0f0";
      description = "Uplink (WAN) interface. Input is default-drop except established/related; LAN is masqueraded out this interface.";
    };

    lan.interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["br-lan"];
      description = "Trusted (LAN) interfaces: their input is accepted and they are forwarded to the WAN.";
    };

    nat.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "IPv4 masquerade (SNAT) for traffic leaving the WAN interface.";
    };

    forwarding = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable IP forwarding and rp_filter anti-spoofing sysctls.";
    };

    ipv6 = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Forward IPv6 as well (no NATv6, so routed prefixes are assumed).";
    };

    suricata = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Send forwarded traffic to Suricata via NFQUEUE. Pair with othrys.services.suricata (mode = \"nfqueue\").";
      };

      queues = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "NFQUEUE count; must match othrys.services.suricata.nfqueue.queues.";
      };
    };

    extraInputRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw nftables rules appended to the filter input chain (e.g. management ports from the WAN).";
    };

    extraForwardRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw nftables rules appended to the filter forward chain (e.g. port forwards, inter-VLAN policy).";
    };

    extraNat = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw nftables rules appended to the NAT postrouting chain (e.g. DNAT/port forwards).";
    };
  };
  # ANCHOR_END: router-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.othrys.services.firewall.enable;
        message = "othrys.services.router installs its own nftables ruleset and disables networking.firewall; do not also enable othrys.services.firewall.";
      }
    ];

    networking.firewall.enable = lib.mkForce false;
    networking.nftables.enable = true;

    boot.kernel.sysctl = lib.mkIf cfg.forwarding (
      {
        "net.ipv4.conf.all.forwarding" = 1;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
      }
      // lib.optionalAttrs cfg.ipv6 {
        "net.ipv6.conf.all.forwarding" = 1;
      }
    );

    networking.nftables.tables = {
      router-filter = {
        family = "inet";
        content = ''
          chain input {
            type filter hook input priority filter; policy drop;

            iifname "lo" accept
            ct state established,related accept
            ct state invalid drop

            ip protocol icmp accept
            ip6 nexthdr icmpv6 accept

            ${lib.optionalString hasLan ''iifname ${lanSet} accept''}
            ${cfg.extraInputRules}
          }

          chain forward {
            type filter hook forward priority filter; policy drop;

            ct state invalid drop
            ${lib.optionalString hasLan ''
            iifname ${lanSet} oifname "${cfg.wan.interface}" ${fwdVerb}
            iifname "${cfg.wan.interface}" oifname ${lanSet} ct state established,related ${fwdVerb}
          ''}
            ${cfg.extraForwardRules}
          }
        '';
      };

      router-nat = lib.mkIf cfg.nat.enable {
        family = "ip";
        content = ''
          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "${cfg.wan.interface}" masquerade
            ${cfg.extraNat}
          }
        '';
      };
    };
  };
}
