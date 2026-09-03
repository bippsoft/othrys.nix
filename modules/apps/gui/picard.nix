# modules/apps/gui/picard.nix
# MusicBrainz Picard, a music tagger
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.picard;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.picard = {
    enable = lib.mkEnableOption "MusicBrainz Picard music tagger";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
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
