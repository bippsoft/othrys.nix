# flake/checks/lib/router-topology.nix
# Routed four-node topology shared by the router VM tests
#
# A router with one WAN and two LAN interfaces, a DHCP client on each LAN and a
# static host on the WAN. `routerModule` is merged into the router node, which
# is how a test turns on more of the router than the plain firewall.
#
# The test driver names interfaces after the position of a VLAN in
# `virtualisation.vlans`, so the router's [1 2 3] become eth1 (WAN), eth2 (LAN
# A) and eth3 (LAN B), while every single-homed node sees its VLAN as eth1.
{
  pkgs,
  inputs,
  routerModule ? {},
}: let
  inherit (pkgs) lib;

  net = {
    wan = {
      router = "192.0.2.1";
      host = "192.0.2.10";
      # The WAN link also carries IPv6. The WAN host advertises the prefix
      # and itself as the default router, which is how an upstream hands a
      # router its IPv6 route.
      prefix6 = "2001:db8:1::";
      router6 = "2001:db8:1::1";
      host6 = "2001:db8:1::10";
    };
    lanA = {
      subnet = "10.10.1.0/24";
      router = "10.10.1.1";
      poolFirst = "10.10.1.100";
      poolLast = "10.10.1.150";
    };
    lanB = {
      subnet = "10.10.2.0/24";
      router = "10.10.2.1";
      poolFirst = "10.10.2.100";
      poolLast = "10.10.2.150";
    };
  };

  ports = {
    wan = 80;
    # Both listen on lanA. Only `interLan` is opened from LAN B by the router's
    # extraForwardRules, so `closed` shows what the generated ruleset does alone.
    interLan = 8081;
    closed = 8080;
    # Listens on every router address and is opened nowhere.
    router = 8080;
    # Arrives on the router's WAN address and is forwarded to lanA's static
    # address on `interLan`.
    forwarded = 8082;
    # Listens on every router address. Opened through the firewall's global
    # list, the way a module's openFirewall does it, so it reaches the LAN and
    # not the WAN.
    opened = 8083;
    # Listens on every router address and is opened on the WAN interface by
    # name, which is the only way a port reaches the WAN.
    wanOpened = 8084;
  };

  # lanA's lease comes from a pool, so the port forward points at a second,
  # fixed address the client adds beside it.
  forwardTarget = "10.10.1.50";

  # Served by Unbound from local-data, since the sandbox has no upstream to ask.
  localName = "wan.example.com";

  httpLog = port: "/var/log/httpd-${toString port}.log";

  # A static page per listener. darkhttpd logs one line per request and the
  # first field is the peer address, which is what the NAT assertion reads.
  httpd = port: body: {
    systemd.services."httpd-${toString port}" = {
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig.ExecStart = "${lib.getExe pkgs.darkhttpd} ${pkgs.writeTextDir "index.html" body} --port ${toString port} --log ${httpLog port}";
    };
  };

  # The driver assigns 192.168.<vlan>.<node> and a 2001:db8 address to every
  # VLAN interface. Both are forced away so the only addresses in play are the
  # ones below and the leases Kea hands out.
  static = address: {
    ipv4.addresses = lib.mkForce [
      {
        inherit address;
        prefixLength = 24;
      }
    ];
    ipv6.addresses = lib.mkForce [];
  };
  static6 = address: address6: {
    ipv4.addresses = lib.mkForce [
      {
        inherit address;
        prefixLength = 24;
      }
    ];
    ipv6.addresses = lib.mkForce [
      {
        address = address6;
        prefixLength = 64;
      }
    ];
  };

  common = {
    imports = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      inputs.sops-nix.nixosModules.sops
      {
        options.stylix = lib.mkOption {
          type = lib.types.attrs;
          default = {};
        };
      }
    ];

    # Four VMs boot at once, so each stays small unless a test needs more.
    virtualisation.memorySize = lib.mkDefault 512;

    # eth0 is the driver's user-mode network. Left on DHCP it installs a default
    # route and a resolver that bypass the router under test.
    networking.useDHCP = false;
    # Keeps the driver's 192.168.x.y address for each node out of /etc/hosts.
    networking.primaryIPAddress = lib.mkForce "";
  };

  # The endpoints run no firewall, so the router is the only filter on the path
  # and a refused connection can only be its doing.
  client = vlan: {
    imports = [common];
    virtualisation.vlans = [vlan];
    networking.firewall.enable = false;
    networking.interfaces.eth1 = {
      ipv4.addresses = lib.mkForce [];
      ipv6.addresses = lib.mkForce [];
      useDHCP = true;
    };
    environment.systemPackages = [pkgs.dig];
  };
in {
  inherit net ports localName forwardTarget;
  wanLog = httpLog ports.wan;

  # Python shared by the test scripts, spliced in ahead of the subtests.
  scriptHelpers = ''
    def fetch(machine, url):
        return machine.succeed(f"curl -sf --max-time 5 {url}").strip()


    def assert_dropped(machine, url):
        # Packets dropped on the path leave curl waiting until it times out,
        # which is exit 28. A closed port or an unreachable network fails
        # faster, with another code, and says nothing about the router.
        status, _ = machine.execute(f"curl -s -o /dev/null --max-time 3 {url}")
        assert status == 28, f"expected {url} to time out, curl exited {status}"
  '';

  nodes = {
    router = {
      imports = [
        common
        routerModule
        (httpd ports.router "router\n")
        (httpd ports.opened "router\n")
        (httpd ports.wanOpened "router\n")
      ];
      networking.firewall.allowedTCPPorts = [ports.opened];
      networking.firewall.interfaces.eth1.allowedTCPPorts = [ports.wanOpened];
      virtualisation.vlans = [1 2 3];
      networking.interfaces = {
        eth1 = static6 net.wan.router net.wan.router6;
        eth2 = static net.lanA.router;
        eth3 = static net.lanB.router;
      };

      othrys.services.router = {
        enable = true;
        wan.interface = "eth1";
        lan.interfaces = ["eth2" "eth3"];
        # The generated forward chain only knows LAN to WAN and its replies.
        # Traffic between LANs is policy the host supplies, replies included.
        extraForwardRules = ''
          iifname "eth3" oifname "eth2" tcp dport ${toString ports.interLan} accept
          iifname "eth2" oifname "eth3" ct state established,related accept
        '';
        portForwards = [
          {
            port = ports.forwarded;
            destination = forwardTarget;
            destinationPort = ports.interLan;
          }
        ];
        # A source rewrite is what the postrouting chain is for. It is here so
        # the ruleset loads with something in that passthrough.
        extraNat = ''
          oifname "eth1" ip saddr ${forwardTarget} masquerade
        '';
      };

      othrys.services.kea = {
        enable = true;
        dhcp4 = {
          interfaces = ["eth2" "eth3"];
          settings.subnet4 =
            lib.imap1 (id: lan: {
              inherit id;
              inherit (lan) subnet;
              pools = [{pool = "${lan.poolFirst} - ${lan.poolLast}";}];
              option-data = [
                {
                  name = "routers";
                  data = lan.router;
                }
                {
                  name = "domain-name-servers";
                  data = lan.router;
                }
              ];
            }) [
              net.lanA
              net.lanB
            ];
        };
      };

      othrys.services.unbound = {
        enable = true;
        interfaces = ["127.0.0.1" net.lanA.router net.lanB.router];
        accessControl = ["${net.lanA.subnet} allow" "${net.lanB.subnet} allow"];
        # unbound.conf wants the record quoted, and the NixOS module writes
        # strings through verbatim.
        settings.server = {
          local-zone = ["example.com. static"];
          local-data = [''"${localName}. IN A ${net.wan.host}"''];
        };
      };
    };

    lanA = {
      imports = [
        (client 2)
        (httpd ports.interLan "lanA\n")
        (httpd ports.closed "lanA\n")
      ];
      # The fixed address the port forward points at, beside the lease.
      networking.localCommands = "ip addr add ${forwardTarget}/24 dev eth1";
    };

    lanB = client 3;

    wan = {
      imports = [
        common
        (httpd ports.wan "wan\n")
      ];
      virtualisation.vlans = [1];
      networking.firewall.enable = false;
      # The upstream router's half: advertise the prefix and a default
      # route, which the router under test only takes with accept_ra = 2.
      services.radvd = {
        enable = true;
        config = ''
          interface eth1 {
            AdvSendAdvert on;
            MinRtrAdvInterval 3;
            MaxRtrAdvInterval 4;
            AdvDefaultLifetime 60;
            prefix ${net.wan.prefix6}/64 {
              AdvOnLink on;
              AdvAutonomous off;
            };
          };
        '';
      };
      networking.interfaces.eth1 = lib.mkMerge [
        (static6 net.wan.host net.wan.host6)
        {
          # Without a route the WAN host could not address a LAN at all, and the
          # forward-drop assertions would pass without the router seeing a packet.
          ipv4.routes = [
            {
              address = "10.10.0.0";
              prefixLength = 16;
              via = net.wan.router;
            }
          ];
        }
      ];
    };
  };
}
