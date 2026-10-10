# modules/hardware/webcam.nix
# Webcam support with V4L2 utilities
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.hardware.webcam;
in {
  options.othrys.hardware.webcam = {
    enable = lib.mkEnableOption "Webcam support";
  };

  config = lib.mkIf cfg.enable {
    # No group membership is added. logind grants the user at the seat access
    # to camera nodes through a udev ACL, and the video group would open the
    # DRM, framebuffer and backlight nodes to that user from every session,
    # an SSH login included.
    environment.systemPackages = with pkgs; [
      v4l-utils
    ];
  };
}
