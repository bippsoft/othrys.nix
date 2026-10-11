# modules/apps/gui/picard.nix
# MusicBrainz Picard, a music tagger
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.picard;
in {
  options.othrys.apps.picard = {
    enable = lib.mkEnableOption "MusicBrainz Picard music tagger";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.persist."apps.picard" = {
      user.directories = [
        ".config/MusicBrainz"
      ];
    };

    othrys.internal.homeConfig."apps.picard" = {
      home.packages = with pkgs; [
        picard
      ];
    };
  };
}
