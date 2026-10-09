# modules/services/router.nix
# L3 router firewall + NAT (nftables). Generates a default-drop `inet` filter
# (input/forward) and an `ip` NAT masquerade from WAN/LAN interface options, with
# an optional NFQUEUE hook that hands forwarded traffic to Suricata (pair with
# othrys.services.suricata mode = "nfqueue").
#
# Thin by design, since interface names and subnets are identity and come from the
# fleet host. Port forwards are declared, since each one is two rules in two
# chains that have to agree. Anything else the generated ruleset doesn't cover
# goes through the raw extraInputRules / extraForwardRules / extraPrerouting /
# extraNat passthroughs.
#
# networking.firewall is off on a router, since this ruleset is the firewall,
# but its port lists are still read. Every module's openFirewall writes
# networking.firewall.allowedTCPPorts or allowedUDPPorts, and on a router
# those open the port on every interface but the WAN. A port reaches the WAN
# only through networking.firewall.interfaces.<wan>.allowed*, which is what
# the tailscale module uses for its own port.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.router;

  hasLan = cfg.lan.interfaces != [];
  hasPrerouting = cfg.portForwards != [] || cfg.extraPrerouting != "";

  # The firewall's port lists, rendered as nftables accepts. The global lists
  # apply to every interface but the WAN; a per-interface list applies to the
  # interface it names, which is how a port is opened on the WAN on purpose.
  fw = config.networking.firewall;
  portSet = ports: ranges: let
    items = map toString ports ++ map (r: "${toString r.from}-${toString r.to}") ranges;
  in
    if items == []
    then null
    else "{ ${lib.concatStringsSep ", " items} }";
  acceptRules = match: lists: let
    tcp = portSet lists.allowedTCPPorts lists.allowedTCPPortRanges;
    udp = portSet lists.allowedUDPPorts lists.allowedUDPPortRanges;
  in
    lib.optionalString (tcp != null) "${match} tcp dport ${tcp} accept\n"
    + lib.optionalString (udp != null) "${match} udp dport ${udp} accept\n";
  openPorts =
    acceptRules ''iifname != "${cfg.wan.interface}"'' fw
    + lib.concatStrings (lib.mapAttrsToList (name: lists: acceptRules ''iifname "${name}"'' lists) fw.interfaces);

  # sysctl names an interface with its dots turned into slashes.
  sysctlInterface = lib.replaceStrings ["."] ["/"] cfg.wan.interface;

  # The last rule of a default-drop chain. The counter shows what the policy
  # dropped, and the log says which packets when a host asks.
  dropRule = chain: "${lib.optionalString cfg.logDrops ''log prefix "router ${chain} drop: " ''}counter drop";
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

  # A port forward is a dnat rule in prerouting, where the kernel rewrites the
  # destination before routing, and an accept in forward for the rewritten
  # connection, which the WAN side's established-only rule would otherwise
  # drop. The accept goes through Suricata like any other forwarded traffic.
  destinationPort = f:
    if f.destinationPort == null
    then f.port
    else f.destinationPort;
  dnatRule = f: ''iifname "${cfg.wan.interface}" ${f.protocol} dport ${toString f.port} dnat to ${f.destination}:${toString (destinationPort f)}'';
  forwardRule = f: ''iifname "${cfg.wan.interface}" ip daddr ${f.destination} ${f.protocol} dport ${toString (destinationPort f)} ct state new ${fwdVerb}'';
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

    logDrops = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Log every packet the input and forward chains drop, through the
        kernel log with a `router input drop:` or `router forward drop:`
        prefix. The counters on those rules are always on; this adds the
        packets themselves, which is useful while bringing a host up and
        noisy on a WAN link afterwards.
      '';
    };

    extraInputRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Raw nftables rules appended to the filter input chain. A port that a
        module opens through `openFirewall` needs nothing here, since the
        firewall's port lists are rendered into this chain for every interface
        but the WAN. A port that must reach the WAN is opened with
        `networking.firewall.interfaces.<wan>.allowedTCPPorts` or the UDP
        list, which this chain renders for that interface alone.
      '';
    };

    extraForwardRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw nftables rules appended to the filter forward chain (e.g. port forwards, inter-VLAN policy).";
    };

    portForwards = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          protocol = lib.mkOption {
            type = lib.types.enum ["tcp" "udp"];
            default = "tcp";
            description = "Transport protocol of the forwarded connections.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = "Port on the WAN interface the connections arrive on.";
          };
          destination = lib.mkOption {
            type = lib.types.str;
            example = "10.0.0.42";
            description = "LAN address the connections are sent to.";
          };
          destinationPort = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = "Port on the destination. The WAN port when null.";
          };
        };
      });
      default = [];
      example = lib.literalExpression ''
        [
          {
            port = 25565;
            destination = "10.0.0.42";
          }
        ]
      '';
      description = ''
        Connections arriving on the WAN interface that are sent on to a LAN
        host. Each entry renders the dnat rule in the NAT prerouting chain and
        the accept in the forward chain that the rewritten connection needs,
        through Suricata when the IPS hook is on.
      '';
    };

    extraPrerouting = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Raw nftables rules appended to the NAT prerouting chain, where a
        `dnat` or `redirect` verb belongs. A connection rewritten here still
        needs its accept in `extraForwardRules` unless `portForwards` made
        it.
      '';
    };

    extraNat = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Raw nftables rules appended to the NAT postrouting chain, after the
        masquerade, for source rewrites such as an exception to it. A `dnat`
        verb is invalid in this chain: `nft --check` accepts it, the kernel
        refuses the whole ruleset at load, and the router comes up with no
        firewall at all. Port forwards go in `portForwards` or
        `extraPrerouting`.
      '';
      example = ''oifname "enp1s0f0" ip saddr 10.0.0.42 snat to 203.0.113.42'';
    };
  };
  # ANCHOR_END: router-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.othrys.services.firewall.enable;
        message = "othrys.services.router installs its own nftables ruleset and disables networking.firewall; do not also enable othrys.services.firewall.";
      }
      {
        # A router with no LAN set, no port list and no input rule accepts
        # nothing but replies and ICMP, which is a host that can be reached
        # from the console alone.
        assertion = hasLan || openPorts != "" || cfg.extraInputRules != "";
        message = "othrys.services.router: with lan.interfaces empty, no firewall port list and no extraInputRules, nothing can reach this host. Name the LAN interfaces, or open a port.";
      }
    ];

    networking.firewall.enable = lib.mkForce false;
    networking.nftables.enable = true;

    # Reverse-path filtering is strict on the WAN, where a packet claiming a
    # LAN source is a spoof, and loose everywhere else. Strict on every
    # interface dropped the routes Tailscale installs and the replies of any
    # multi-homed path, since those arrive on an interface the route back
    # does not use.
    boot.kernel.sysctl = lib.mkIf cfg.forwarding (
      {
        "net.ipv4.conf.all.forwarding" = 1;
        "net.ipv4.conf.all.rp_filter" = 2;
        "net.ipv4.conf.default.rp_filter" = 2;
        "net.ipv4.conf.${sysctlInterface}.rp_filter" = 1;
      }
      // lib.optionalAttrs cfg.ipv6 {
        "net.ipv6.conf.all.forwarding" = 1;
        # A forwarding host ignores router advertisements, so the WAN would
        # get no IPv6 default route from the upstream router. 2 accepts them
        # on that interface with forwarding on.
        "net.ipv6.conf.${sysctlInterface}.accept_ra" = 2;
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

            # ICMP from inside is unrestricted. From the WAN it is the types a
            # host needs to be reachable and to learn its path, with echo
            # requests rate-limited. `meta l4proto` matches ICMPv6 behind
            # extension headers, where `ip6 nexthdr` saw only the first one.
            iifname != "${cfg.wan.interface}" ip protocol icmp accept
            iifname != "${cfg.wan.interface}" meta l4proto ipv6-icmp accept
            iifname "${cfg.wan.interface}" ip protocol icmp icmp type echo-request limit rate 10/second accept
            iifname "${cfg.wan.interface}" ip protocol icmp icmp type { destination-unreachable, time-exceeded, parameter-problem } accept
            iifname "${cfg.wan.interface}" meta l4proto ipv6-icmp icmpv6 type echo-request limit rate 10/second accept
            iifname "${cfg.wan.interface}" meta l4proto ipv6-icmp icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert } accept

            ${lib.optionalString hasLan ''iifname ${lanSet} accept''}
            ${openPorts}
            ${cfg.extraInputRules}
            ${dropRule "input"}
          }

          chain forward {
            type filter hook forward priority filter; policy drop;

            ct state invalid drop
            ${lib.optionalString hasLan ''
            iifname ${lanSet} oifname "${cfg.wan.interface}" ${fwdVerb}
            iifname "${cfg.wan.interface}" oifname ${lanSet} ct state established,related ${fwdVerb}
          ''}
            ${lib.concatMapStringsSep "\n" forwardRule cfg.portForwards}
            ${cfg.extraForwardRules}
            ${dropRule "forward"}
          }
        '';
      };

      # The nat table exists for the masquerade, for a port forward, or for
      # both. Each chain is rendered only when something goes in it.
      router-nat = lib.mkIf (cfg.nat.enable || hasPrerouting) {
        family = "ip";
        content = ''
          ${lib.optionalString hasPrerouting ''
            chain prerouting {
              type nat hook prerouting priority dstnat; policy accept;
              ${lib.concatMapStringsSep "\n" dnatRule cfg.portForwards}
              ${cfg.extraPrerouting}
            }
          ''}
          ${lib.optionalString cfg.nat.enable ''
            chain postrouting {
              type nat hook postrouting priority srcnat; policy accept;
              oifname "${cfg.wan.interface}" masquerade
              ${cfg.extraNat}
            }
          ''}
        '';
      };
    };
  };
}
