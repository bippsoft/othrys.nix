# modules/hardware/ntsync.nix
# The ntsync driver for Wine and Proton, opened to the active session's user
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.hardware.ntsync;
  kernelVersion = config.boot.kernelPackages.kernel.version;
in {
  # ANCHOR: ntsync-options
  options.othrys.hardware.ntsync = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Load the ntsync driver and give the active session's user access to
        `/dev/ntsync`. Proton 10 and later use it for Windows synchronization
        primitives when the device is present and writable, which lowers the
        CPU cost of games that wait on many objects. Any Wine build with
        ntsync support uses it the same way, so it serves Lutris, Heroic or
        Bottles as well as Steam. The kernel ships the driver from 6.14 as a
        module that nothing loads, and no udev rule grants access to it.
        `othrys.apps.gaming.steam` turns it on by default on such a kernel.
      '';
    };
  };
  # ANCHOR_END: ntsync-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.versionAtLeast kernelVersion "6.14";
        message = "othrys.hardware.ntsync: the ntsync driver ships with kernel 6.14 and later, and this host runs ${kernelVersion}. Choose a newer kernel or turn ntsync off.";
      }
    ];

    # The kernel ships the driver as a module that nothing loads.
    boot.kernelModules = ["ntsync"];

    # uaccess hands the device to whoever holds the active seat, as logind
    # does for input and sound devices, rather than to every account.
    services.udev.extraRules = ''
      KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
    '';
  };
}
