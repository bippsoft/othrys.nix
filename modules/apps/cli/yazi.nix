# modules/apps/cli/yazi.nix
# Yazi terminal file manager
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.yazi;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.yazi = {
    enable = lib.mkEnableOption "Yazi terminal file manager";
  };

  config = lib.mkIf cfg.enable {
    # Persist yazi state (file operation history, last directory, etc.)
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".local/state/yazi"
      ];
    };

    othrys.internal.homeConfig."apps.yazi" = {
      programs.yazi = {
        enable = true;

        # Shell wrapper, "yy" to launch yazi and cd on exit
        # "y" alone would collide with the yarn alias in the zsh config.
        shellWrapperName = "yy";

        enableZshIntegration = true;
        enableBashIntegration = true;

        settings = {
          mgr = {
            show_hidden = true;
            sort_by = "natural";
            sort_dir_first = true;
            linemode = "size";
            show_symlink = true;
          };

          preview = {
            max_width = 1000;
            max_height = 1000;
          };
        };
      };

      # Dependencies for previews and extended functionality
      home.packages = with pkgs;
        [
          file # Required: file type detection
          ffmpeg # Video thumbnails
          p7zip # Archive extraction and preview
          poppler-utils # PDF preview
          fd # File searching
          ripgrep # File content searching
          fzf # Quick file subtree navigation
          zoxide # Historical directory navigation
          jq # JSON preview
          resvg # SVG preview
          imagemagick # Font, HEIC, JPEG XL preview
        ]
        # Yank-to-clipboard needs a Wayland session, while yazi itself is a TUI
        # usable over SSH, so keep the dep off headless hosts.
        ++ lib.optional config.othrys.desktop.graphical wl-clipboard;
    };
  };
}
