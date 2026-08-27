# modules/hardware/webcam.nix
# Webcam support with V4L2 utilities
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.hardware.webcam;
in {
  options.othrys.hardware.webcam = {
    enable = lib.mkEnableOption "Webcam support";
  };

  config = lib.mkIf cfg.enable {
    # Group membership only when othrys manages the user account (writing
    # users.users.<name> otherwise materializes a phantom user).
    users.users = lib.mkIf usersEnabled {
      ${username}.extraGroups = ["video"];
    };

    environment.systemPackages = with pkgs; [
      v4l-utils
    ];
  };
}
