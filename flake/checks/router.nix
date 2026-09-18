# flake/checks/router.nix
# EXTENDED. Runtime proof for the router, Kea and Unbound modules on the
# topology in ./lib/router-topology.nix. Two LAN clients take a lease and a
# resolver from the router, reach a WAN host through the masquerade, and the
# default-drop input and forward chains are probed from both sides. Every
# refusal is paired with a connection that does get through, so a listener
# that never started cannot pass for a firewall that works.
{
  pkgs,
  inputs,
}: let
  topology = import ./lib/router-topology.nix {inherit pkgs inputs;};
  inherit (topology) net ports;
in
  pkgs.testers.runNixOSTest {
    name = "othrys-router";
    node.specialArgs = {inherit inputs;};

    inherit (topology) nodes;

    testScript = ''
      import ipaddress
      import json

      wan_url = "http://${net.wan.host}:${toString ports.wan}/"


      def lease(client):
          client.wait_until_succeeds("ip -4 -o addr show dev eth1 | grep -q 'inet '")
          info = json.loads(client.succeed("ip -j -4 addr show dev eth1"))
          return info[0]["addr_info"][0]["local"]


      ${topology.scriptHelpers}

      start_all()
      router.wait_for_unit("nftables.service")
      router.wait_for_unit("kea-dhcp4-server.service")
      router.wait_for_unit("unbound.service")
      router.wait_for_open_port(${toString ports.router})
      wan.wait_for_open_port(${toString ports.wan})
      lanA.wait_for_open_port(${toString ports.interLan})
      lanA.wait_for_open_port(${toString ports.closed})

      with subtest("each LAN client holds a Kea lease from its own pool"):
          pools = {
              lanA: ("${net.lanA.poolFirst}", "${net.lanA.poolLast}", "${net.lanA.router}"),
              lanB: ("${net.lanB.poolFirst}", "${net.lanB.poolLast}", "${net.lanB.router}"),
          }
          address: dict[str, str] = {}
          for client, (first, last, gateway) in pools.items():
              address[client.name] = lease(client)
              leased = ipaddress.ip_address(address[client.name])
              assert ipaddress.ip_address(first) <= leased <= ipaddress.ip_address(last), (
                  f"{client.name} holds {leased}, outside {first} - {last}"
              )
              router.succeed(f"grep -q '^{leased},' /var/lib/kea/dhcp4.leases")
              client.succeed(f"ip route show default | grep -q 'via {gateway} dev eth1'")

      with subtest("clients resolve a local name through Unbound on the router"):
          for client, (_, _, gateway) in pools.items():
              client.succeed(f"grep -q '^nameserver {gateway}$' /etc/resolv.conf")
              answer = client.succeed("dig +short ${topology.localName}").strip()
              assert answer == "${net.wan.host}", f"{client.name} resolved {answer!r}"

      with subtest("LAN traffic leaves the WAN masqueraded as the router"):
          assert fetch(lanA, wan_url) == "wan"
          peer = wan.succeed("tail -n 1 ${topology.wanLog}").split()[0]
          assert peer == "${net.wan.router}", f"the WAN host saw {peer}"

      with subtest("WAN to LAN forwarding is dropped"):
          listener = f"http://{address['lanA']}:${toString ports.interLan}/"
          assert fetch(lanB, listener) == "lanA"
          assert_dropped(wan, listener)

      with subtest("LAN to LAN forwarding is dropped unless extraForwardRules opens it"):
          closed = f"http://{address['lanA']}:${toString ports.closed}/"
          assert fetch(router, closed) == "lanA"
          assert_dropped(lanB, closed)
          assert fetch(lanB, f"http://{address['lanA']}:${toString ports.interLan}/") == "lanA"

      with subtest("a router port nobody opened is closed to the WAN"):
          assert fetch(lanA, "http://${net.lanA.router}:${toString ports.router}/") == "router"
          wan.succeed("ping -c 1 -W 3 ${net.wan.router}")
          assert_dropped(wan, "http://${net.wan.router}:${toString ports.router}/")
    '';
  }
