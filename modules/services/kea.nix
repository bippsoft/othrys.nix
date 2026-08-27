# modules/services/kea.nix
# Kea DHCP (DHCPv4/DHCPv6), a thin wrapper over services.kea with sane defaults
# (bound interfaces + persistent memfile leases). Subnets, reservations, and
# options are identity and come from the fleet via `settings`, which is
# deep-merged over the defaults.
#
# Since Kea 2.6 (NixOS 24.11) every subnet entry needs a unique mandatory
# `id`, e.g. `subnet4 = [{ id = 1; subnet = "10.0.0.0/24"; ... }]`.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.kea;

  mkPool = family: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = family == "4";
      description = "Enable the Kea DHCP${family} server.";
    };

    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["br-lan"];
      description = "Interfaces the DHCP${family} server listens on.";
    };

    leasesFile = lib.mkOption {
      # Mutable runtime state rather than a credential, so it stays a plain str.
      type = lib.types.str;
      default = "/var/lib/kea/dhcp${family}.leases";
      description = "memfile lease database path.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Kea DHCP${family} settings, deep-merged over the defaults (put subnet${family}/reservations/option-data here).";
      example = lib.literalExpression ''
        {
          subnet${family} = [
            {
              id = 1;
              subnet = "10.0.0.0/24";
              pools = [{ pool = "10.0.0.100 - 10.0.0.240"; }];
              option-data = [{ name = "routers"; data = "10.0.0.1"; }];
            }
          ];
        }
      '';
    };
  };

  mkSettings = pool:
    lib.recursiveUpdate {
      interfaces-config.interfaces = pool.interfaces;
      lease-database = {
        type = "memfile";
        persist = true;
        name = pool.leasesFile;
      };
    }
    pool.settings;
in {
  # ANCHOR: kea-options
  options.othrys.services.kea = {
    enable = lib.mkEnableOption "Kea DHCP server";

    dhcp4 = mkPool "4";
    dhcp6 = mkPool "6";
  };
  # ANCHOR_END: kea-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.dhcp4.enable || cfg.dhcp4.interfaces != [];
        message = "othrys.services.kea: dhcp4.interfaces must list at least one interface.";
      }
      {
        assertion = !cfg.dhcp6.enable || cfg.dhcp6.interfaces != [];
        message = "othrys.services.kea: dhcp6.interfaces must list at least one interface.";
      }
    ];

    services.kea.dhcp4 = lib.mkIf cfg.dhcp4.enable {
      enable = true;
      settings = mkSettings cfg.dhcp4;
    };

    services.kea.dhcp6 = lib.mkIf cfg.dhcp6.enable {
      enable = true;
      settings = mkSettings cfg.dhcp6;
    };
  };
}
