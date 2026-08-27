# modules/hardware/usb.nix
# USB hardware support and utilities
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.hardware.usb;
in {
  options.othrys.hardware.usb = {
    enable = lib.mkEnableOption "USB hardware support and utilities";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      usbutils
    ];
  };
}
