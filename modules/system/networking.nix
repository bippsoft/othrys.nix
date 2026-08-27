# modules/system/networking.nix
# systemd-networkd networking: per-interface DHCP/static plus router topology
# helpers (bridges, VLANs, enslavement). IP forwarding lives in
# othrys.services.router. Anything not modelled here (IPv6 prefix delegation,
# policy routing, bonds) is set through `systemd.network.*` directly.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.networking;

  interfaceType = lib.types.submodule {
    options = {
      match = lib.mkOption {
        type = lib.types.str;
        description = "Interface match pattern (name or glob).";
        example = "enp5s0";
      };

      dhcp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable DHCPv4 on this interface, by setting systemd-networkd's
          `DHCP = "ipv4"`.

          This governs IPv4 alone. Turning it off does not make the interface
          statically addressed, since `ipv6` independently controls Router
          Advertisements and leaves the interface with SLAAC addresses. An
          interface with no automatic addressing at all needs `dhcp = false`
          and `ipv6 = false` together.
        '';
      };

      ipv6 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Accept IPv6 Router Advertisements, which is how the interface picks
          up SLAAC addresses and a default route. Independent of `dhcp`, which
          covers IPv4 only.
        '';
      };

      address = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["10.0.0.1/24"];
        description = "Static addresses (CIDR) to assign to the interface.";
      };

      bridge = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Enslave this interface to the named bridge (declared under `bridges`).";
      };

      vlans = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "VLAN netdevs (declared under `vlans`) carried on this interface (trunk port).";
      };

      requiredForOnline = lib.mkOption {
        type = lib.types.enum ["routable" "carrier" "degraded" "enslaved" "no"];
        default = "routable";
        description = "When this interface counts as 'online' for network-online.target (use 'enslaved' for bridge members).";
      };
    };
  };

  bridgeType = lib.types.submodule {
    options.address = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["10.0.0.1/24"];
      description = "Static addresses (CIDR) assigned to the bridge itself.";
    };
  };

  vlanType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.ints.between 1 4094;
        description = "802.1Q VLAN ID.";
      };
      address = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Static addresses (CIDR) assigned to the VLAN interface.";
      };
    };
  };

  interfaceNetworks = lib.mapAttrs' (name: iface:
    lib.nameValuePair "10-${name}" {
      matchConfig.Name = iface.match;
      networkConfig =
        {
          DHCP =
            if iface.dhcp
            then "ipv4"
            else "no";
          IPv6AcceptRA = iface.ipv6;
        }
        // lib.optionalAttrs (iface.bridge != null) {
          Bridge = iface.bridge;
          ConfigureWithoutCarrier = true;
        };
      inherit (iface) address;
      vlan = iface.vlans;
      linkConfig.RequiredForOnline = iface.requiredForOnline;
    })
  cfg.interfaces;

  bridgeNetworks = lib.mapAttrs' (name: br:
    lib.nameValuePair "15-${name}" {
      matchConfig.Name = name;
      inherit (br) address;
      networkConfig.ConfigureWithoutCarrier = true;
    })
  cfg.bridges;

  vlanNetworks = lib.mapAttrs' (name: v:
    lib.nameValuePair "16-${name}" {
      matchConfig.Name = name;
      inherit (v) address;
    })
  cfg.vlans;
in {
  options.othrys.system.networking = {
    enable = lib.mkEnableOption "systemd-networkd networking";

    interfaces = lib.mkOption {
      type = lib.types.attrsOf interfaceType;
      default = {};
      description = "Per-interface network configurations.";
      example = lib.literalExpression ''
        {
          wan = {
            match = "enp1s0f0";
            dhcp = true;
            requiredForOnline = "routable";
          };
          lan-port = {
            match = "enp1s0f1";
            bridge = "br-lan";
            requiredForOnline = "enslaved";
          };
        }
      '';
    };

    bridges = lib.mkOption {
      type = lib.types.attrsOf bridgeType;
      default = {};
      description = "Bridge netdevs; enslave interfaces to them via interfaces.<name>.bridge.";
      example = lib.literalExpression ''{ br-lan.address = ["10.0.0.1/24"]; }'';
    };

    vlans = lib.mkOption {
      type = lib.types.attrsOf vlanType;
      default = {};
      description = "VLAN netdevs; carry them on a trunk via interfaces.<name>.vlans.";
      example = lib.literalExpression ''{ vlan100 = { id = 100; address = ["10.100.0.1/24"]; }; }'';
    };

    waitOnline = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Wait for network to be online before reaching network-online.target.";
      };

      timeout = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 10;
        description = "Seconds to wait for network before giving up.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable legacy dhcpcd
    networking.useDHCP = false;

    # Enable systemd-networkd
    systemd.network.enable = true;

    systemd.network.netdevs =
      lib.mapAttrs' (name: _:
        lib.nameValuePair "20-${name}" {
          netdevConfig = {
            Kind = "bridge";
            Name = name;
          };
        })
      cfg.bridges
      // lib.mapAttrs' (name: v:
        lib.nameValuePair "25-${name}" {
          netdevConfig = {
            Kind = "vlan";
            Name = name;
          };
          vlanConfig.Id = v.id;
        })
      cfg.vlans;

    systemd.network.networks = interfaceNetworks // bridgeNetworks // vlanNetworks;

    # Wait-online configuration
    systemd.network.wait-online = {
      inherit (cfg.waitOnline) enable timeout;
    };
  };
}
