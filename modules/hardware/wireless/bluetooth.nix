# modules/hardware/wireless/bluetooth.nix
# Bluetooth support with persistence
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.hardware.wireless.bluetooth;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
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
    # Persistence for Bluetooth pairings
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/bluetooth";
          user = "root";
          group = "root";
          mode = "0755";
        }
      ];
    };

    hardware.bluetooth = {
      enable = true;
      inherit (cfg) powerOnBoot;

      settings = {
        General = {
          # Enable A2DP sink (high quality audio)
          Enable = "Source,Sink,Media,Socket";
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
