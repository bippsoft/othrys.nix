# flake/checks/router-eval.nix
# CORE. The router's rendered ruleset, read back from an evaluated host. A
# dnat verb in the postrouting chain passes `nft --check` and fails in the
# kernel, which no evaluation can see, so what is pinned here is that a port
# forward lands in the chains it belongs to and that the passthroughs go where
# their names say.
{
  hostConfig,
  mkExpectations,
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
        othrys.services.router = {
          enable = true;
          wan.interface = "wan0";
          lan.interfaces = ["lan0"];
        };
      }
      extra
    ];

  tables = cfg: cfg.networking.nftables.tables;
  hasInfix = needle: s: builtins.match ".*${needle}.*" s != null;
  # The chain a rule sits in: everything between its `chain <name> {` and the
  # closing brace on a line of its own. An interface set such as `{ "lan0" }`
  # closes inline and is not the end of the chain.
  chain = name: content: let
    parts = builtins.split "chain ${name} [{]" content;
  in
    if builtins.length parts < 3
    then ""
    else builtins.head (builtins.split "\n *[}]" (builtins.elemAt parts 2));

  plain = host {};
  forwarded = host {
    othrys.services.router.portForwards = [
      {
        port = 25565;
        destination = "10.0.0.42";
      }
      {
        protocol = "udp";
        port = 51820;
        destination = "10.0.0.7";
        destinationPort = 51821;
      }
    ];
    othrys.services.router.extraNat = ''oifname "wan0" ip saddr 10.0.0.42 snat to 203.0.113.42'';
  };
  ips = host {
    othrys.services.router.suricata = {
      enable = true;
      queues = 2;
    };
    othrys.services.router.portForwards = [
      {
        port = 25565;
        destination = "10.0.0.42";
      }
    ];
  };
  noMasquerade = host {
    othrys.services.router.nat.enable = false;
    othrys.services.router.extraPrerouting = ''iifname "wan0" tcp dport 2222 redirect to :22'';
  };

  natOf = cfg: (tables cfg).router-nat.content;
  filterOf = cfg: (tables cfg).router-filter.content;

  # Ports opened the way every module does it, through the firewall's lists,
  # and one opened on the WAN by naming the interface.
  opened = host {
    othrys.services.ssh = {
      enable = true;
      server.enable = true;
    };
    othrys.services.tailscale.enable = true;
    networking.firewall.allowedUDPPortRanges = [
      {
        from = 60000;
        to = 61000;
      }
    ];
    networking.firewall.interfaces.wan0.allowedTCPPorts = [8443];
    networking.firewall.interfaces."eth0.100".allowedTCPPorts = [8080];
  };
  input = chain "input" (filterOf opened);
  vlanWan = host ({lib, ...}: {othrys.services.router.wan.interface = lib.mkForce "eth0.100";});
in
  mkExpectations "othrys-eval-router" {
    "a port opened by a module reaches every interface but the WAN" = hasInfix ''iifname != "wan0" tcp dport [{] 22 [}] accept'' input;
    "a UDP range opened by the host reaches every interface but the WAN" = hasInfix ''iifname != "wan0" udp dport [{] 41641, 60000-61000 [}] accept'' input;
    "a port named on the WAN interface is opened there" = hasInfix ''iifname "wan0" tcp dport [{] 8443 [}] accept'' input;
    "tailscale opens its port on the WAN of a router" = hasInfix ''iifname "wan0" udp dport [{] 41641 [}] accept'' input;
    "a port named on another interface is opened there alone" = hasInfix ''iifname "eth0.100" tcp dport [{] 8080 [}] accept'' input;
    "no port list is rendered when none is set" = !hasInfix "dport" (chain "input" (filterOf plain));
    "rp_filter is loose on all" = plain.boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" == 2;
    "rp_filter is strict on the WAN interface" = plain.boot.kernel.sysctl."net.ipv4.conf.wan0.rp_filter" == 1;
    "a WAN interface with a dot is named with a slash for sysctl" = vlanWan.boot.kernel.sysctl ? "net.ipv4.conf.eth0/100.rp_filter";
    "no prerouting chain is rendered without a port forward" = !hasInfix "prerouting" (natOf plain);
    "the masquerade is in postrouting" = hasInfix "masquerade" (chain "postrouting" (natOf plain));
    "a port forward renders its dnat rule in prerouting" = hasInfix ''iifname "wan0" tcp dport 25565 dnat to 10.0.0.42:25565'' (chain "prerouting" (natOf forwarded));
    "a port forward with its own destination port renders both ports" = hasInfix "udp dport 51820 dnat to 10.0.0.7:51821" (chain "prerouting" (natOf forwarded));
    "a port forward renders its accept in the forward chain" = hasInfix "ip daddr 10.0.0.42 tcp dport 25565 ct state new accept" (chain "forward" (filterOf forwarded));
    "the udp forward accepts on the destination port" = hasInfix "ip daddr 10.0.0.7 udp dport 51821 ct state new accept" (chain "forward" (filterOf forwarded));
    "extraNat lands in postrouting" = hasInfix "snat to 203.0.113.42" (chain "postrouting" (natOf forwarded));
    "extraNat does not land in prerouting" = !hasInfix "snat to" (chain "prerouting" (natOf forwarded));
    "no dnat rule is rendered in postrouting" = !hasInfix "dnat" (chain "postrouting" (natOf forwarded));
    "a forwarded connection goes through the IPS queue" = hasInfix "ip daddr 10.0.0.42 tcp dport 25565 ct state new queue num 0-1 fanout,bypass" (chain "forward" (filterOf ips));
    "extraPrerouting renders a prerouting chain without the masquerade" = hasInfix "redirect to :22" (chain "prerouting" (natOf noMasquerade)) && !hasInfix "postrouting" (natOf noMasquerade);
  }
