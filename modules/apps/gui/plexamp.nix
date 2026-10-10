# modules/apps/gui/plexamp.nix
# Plexamp music player
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.plexamp;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.plexamp = {
    enable = lib.mkEnableOption "Plexamp music player";
  };

  config = lib.mkIf cfg.enable {
    # nixpkgs ships plexamp for some platforms only. Without this the host fails
    # deep inside the package set with a message that does not name the option.
    assertions = [
      {
        assertion = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.plexamp;
        message = "othrys.apps.plexamp: nixpkgs does not provide plexamp for ${pkgs.stdenv.hostPlatform.system}. Turn the module off on this host.";
      }
    ];

    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      # The directory holds the Plex auth token.
      users.${username}.directories = [
        {
          directory = ".config/Plexamp";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.plexamp" = {
      home.packages = with pkgs; [plexamp];
    };
  };
}
