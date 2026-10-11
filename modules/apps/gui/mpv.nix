# modules/apps/gui/mpv.nix
# mpv media player
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.mpv;
in {
  options.othrys.apps.mpv = {
    enable = lib.mkEnableOption "mpv media player";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.persist."apps.mpv" = {
      user.directories = [
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
