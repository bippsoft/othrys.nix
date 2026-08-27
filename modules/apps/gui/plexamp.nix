# modules/apps/gui/plexamp.nix
# Plexamp music player
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.plexamp;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.plexamp = {
    enable = lib.mkEnableOption "Plexamp music player";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/Plexamp"
      ];
    };

    home-manager.users.${username} = {
      home.packages = with pkgs; [plexamp];
    };
  };
}
