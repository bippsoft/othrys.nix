# modules/apps/gui/mpv.nix
# mpv media player
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.mpv;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.mpv = {
    enable = lib.mkEnableOption "mpv media player";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/mpv"
        ".local/state/mpv"
      ];
    };

    othrys.internal.homeConfig."apps.mpv" = {
      programs.mpv = {
        enable = true;

        config = {
          # Video
          vo = "gpu-next";
          gpu-api = "vulkan";
          hwdec = "auto-safe";

          # Audio
          volume = 100;
          volume-max = 150;

          # OSD
          osd-bar = "no";
          osd-font-size = 32;

          # Subtitles
          sub-auto = "fuzzy";
          sub-font-size = 40;

          # Screenshots
          screenshot-directory = "~/Pictures/Screenshots";
          screenshot-format = "png";

          # Misc
          save-position-on-quit = true;
          keep-open = "yes";
        };

        bindings = {
          "l" = "seek 5";
          "h" = "seek -5";
          "j" = "seek -60";
          "k" = "seek 60";
          "S" = "cycle sub";
          "A" = "cycle audio";
        };
      };
    };
  };
}
