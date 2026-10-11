# modules/hardware/wireless/bluetooth.nix
# Bluetooth support with persistence
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.hardware.wireless.bluetooth;
in {
  options.othrys.hardware.wireless.bluetooth = {
    enable = lib.mkEnableOption "Bluetooth support";

    powerOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Power on Bluetooth adapter at boot.";
    };

    experimental = lib.mkEnableOption "BlueZ experimental features (e.g. device battery reporting); exposes experimental D-Bus interfaces";
  };

  config = lib.mkIf cfg.enable {
    # Pairings. The tree holds the link keys of every paired device, and
    # bluetoothd creates it 0700, so the persisted directory matches.
    othrys.internal.persist."hardware.wireless.bluetooth" = {
      directories = [
        {
          directory = "/var/lib/bluetooth";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    hardware.bluetooth = {
      enable = true;
      inherit (cfg) powerOnBoot;

      settings = {
        General = {
          # Opt-in experimental features (e.g. battery reporting / extra codecs)
          Experimental = cfg.experimental;
        };
      };
    };

    # Blueman GTK tray applet, desktop hosts only. Headless BT hosts (audio sinks,
    # sensors) manage devices with bluetoothctl and skip the GUI closure.
    services.blueman.enable = config.othrys.desktop.graphical;
  };
}
