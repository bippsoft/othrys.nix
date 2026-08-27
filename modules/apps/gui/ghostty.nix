# modules/apps/gui/ghostty.nix
# Ghostty terminal emulator
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.ghostty;
in {
  options.othrys.apps.ghostty = {
    enable = lib.mkEnableOption "Ghostty terminal emulator";

    # Shell integration
    shellIntegration = {
      zsh = lib.mkEnableOption "Zsh shell integration";
      bash = lib.mkEnableOption "Bash shell integration";
    };

    # Feature toggles
    batSyntax = lib.mkEnableOption "Ghostty config syntax highlighting for bat";
    vimSyntax = lib.mkEnableOption "Ghostty config syntax highlighting for Vim";
    copyOnSelect = lib.mkEnableOption "automatic copy to clipboard on text selection";
    mouseHideWhileTyping = lib.mkEnableOption "hiding mouse cursor while typing";

    # Keybindings
    keybindings = {
      enable = lib.mkEnableOption "custom Ghostty keybindings";
      clearDefaults = lib.mkEnableOption "clearing all default keybindings";
      extra = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [
          "ctrl+shift+f=toggle_fullscreen"
          "ctrl+shift+z=toggle_split_zoom"
        ];
        description = "Additional keybindings in Ghostty format (trigger=action).";
      };
    };

    # Window / GTK
    window = {
      decoration = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to show window decorations (CSD).";
      };

      gtkTitlebar = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to show the GTK titlebar.";
      };

      padding = {
        x = lib.mkOption {
          type = lib.types.int;
          default = 8;
          description = "Horizontal window padding in pixels.";
        };
        y = lib.mkOption {
          type = lib.types.int;
          default = 8;
          description = "Vertical window padding in pixels.";
        };
      };
    };

    # Cursor
    cursor = {
      style = lib.mkOption {
        type = lib.types.enum ["block" "bar" "underline"];
        default = "block";
        description = "Cursor shape style.";
      };
      blink = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether the cursor blinks.";
      };
    };

    # Scrollback
    scrollbackLines = lib.mkOption {
      type = lib.types.int;
      default = 10000;
      description = "Number of scrollback lines to retain.";
    };

    # Extra settings passthrough
    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      example = {
        bold-is-bright = false;
        confirm-close-surface = false;
      };
      description = "Additional Ghostty settings merged into the configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = {
      programs.ghostty = {
        enable = true;

        # Shell integration toggles
        enableZshIntegration = cfg.shellIntegration.zsh;
        enableBashIntegration = cfg.shellIntegration.bash;

        # Syntax highlighting
        installBatSyntax = cfg.batSyntax;
        installVimSyntax = cfg.vimSyntax;

        # Keybindings
        clearDefaultKeybinds = cfg.keybindings.clearDefaults;

        settings =
          {
            # Cursor
            cursor-style = cfg.cursor.style;
            cursor-style-blink = cfg.cursor.blink;

            # Window / GTK
            window-decoration = cfg.window.decoration;
            window-padding-x = cfg.window.padding.x;
            window-padding-y = cfg.window.padding.y;
            gtk-titlebar = cfg.window.gtkTitlebar;

            # Scrollback
            scrollback-limit = cfg.scrollbackLines;

            # Mouse
            mouse-hide-while-typing = cfg.mouseHideWhileTyping;
            copy-on-select = cfg.copyOnSelect;

            # Behaviour
            working-directory = "home";
            confirm-close-surface = false;
            gtk-single-instance = false;
          }
          // lib.optionalAttrs cfg.keybindings.enable {
            keybind =
              [
                "ctrl+shift+c=copy_to_clipboard"
                "ctrl+shift+v=paste_from_clipboard"
                "ctrl+shift+t=new_tab"
                "ctrl+shift+w=close_surface"
                "ctrl+shift+l=new_split:right"
                "ctrl+shift+j=new_split:down"
                "ctrl+shift+h=new_split:left"
                "ctrl+shift+k=new_split:up"
                "alt+l=goto_split:right"
                "alt+j=goto_split:down"
                "alt+h=goto_split:left"
                "alt+k=goto_split:up"
                "ctrl+shift+equal=increase_font_size:1"
                "ctrl+shift+minus=decrease_font_size:1"
                "ctrl+shift+0=reset_font_size"
              ]
              ++ cfg.keybindings.extra;
          }
          // cfg.extraSettings;
      };
    };
  };
}
