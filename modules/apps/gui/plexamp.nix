# modules/apps/gui/plexamp.nix
# Plexamp music player
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.plexamp;
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

    othrys.internal.persist."apps.plexamp" = {
      # The directory holds the Plex auth token.
      user.directories = [
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
