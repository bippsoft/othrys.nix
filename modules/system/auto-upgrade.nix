# modules/system/auto-upgrade.nix
# Unattended flake upgrades for headless hosts, pulling the fleet flake on a
# schedule, switch, optionally reboot inside a window. Failures push through
# othrys-notify when the notify module is enabled. An upgrade that silently
# stops applying is how fleets rot.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.autoUpgrade;
in {
  # ANCHOR: auto-upgrade-options
  options.othrys.system.autoUpgrade = {
    enable = lib.mkEnableOption "unattended nixos-rebuild from the fleet flake";

    flake = lib.mkOption {
      type = lib.types.str;
      example = "github:example/fleet";
      description = "Flake URI the host upgrades from (the FLEET repo, not this library). Identity-shaped, set from the consuming host. Private repos need fetch credentials (e.g. a netrc via secrets).";
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = "systemd calendar expression for the upgrade timer (daily at 04:00 by default, since servers want security fixes promptly).";
    };

    allowReboot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Reboot when the new generation requires it (kernel/systemd changes). Off by default, so enable deliberately with a rebootWindow.";
    };

    rebootWindow = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
      default = null;
      example = {
        lower = "03:00";
        upper = "05:00";
      };
      description = "Time window reboots are confined to (with allowReboot). Null reboots whenever the upgrade lands.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = "Random delay added to the timer so a fleet doesn't hit the flake host simultaneously.";
    };

    flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra flags passed to nixos-rebuild.";
    };
  };
  # ANCHOR_END: auto-upgrade-options

  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      inherit (cfg) flake dates allowReboot rebootWindow randomizedDelaySec flags;
    };

    # A failed upgrade must reach a human (cross-module conditional, no
    # hard dependency on notify).
    systemd.services.nixos-upgrade = lib.mkIf config.othrys.services.notify.enable {
      onFailure = ["notify-failure@%n.service"];
    };
  };
}
