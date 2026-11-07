# modules/apps/gui/ghostty.nix
# Ghostty terminal emulator
{lib, ...}: let
  # One value of a Ghostty config key. The file is flat `key = value` lines,
  # and a key that repeats, such as keybind or palette, is given as a list.
  settingAtom = lib.types.nullOr (lib.types.oneOf [lib.types.bool lib.types.int lib.types.float lib.types.str]);
in {
  imports = [
    (lib.mkRemovedOptionModule ["othrys" "apps" "ghostty" "scrollbackLines"] "Ghostty measures its scrollback in bytes, so the value was never a line count. Set othrys.apps.ghostty.scrollbackLimit, in bytes, instead.")
  ];

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
    # Ghostty's `scrollback-limit` is a size in bytes and not a line count.
    # The default is Ghostty's own, 10 MB for each terminal surface.
    scrollbackLimit = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 10000000;
      example = 50000000;
      description = "Scrollback each terminal surface retains, in bytes. A line of 80 plain characters takes roughly 80 bytes.";
    };

    # Extra settings passthrough
    extraSettings = lib.mkOption {
      # What programs.ghostty.settings accepts upstream, spelled out. The
      # upstream key-value type also turns a lone value into a one-element
      # list, and that coercion is left to it so a value read back from this
      # option is the value that was written.
      type = lib.types.attrsOf (lib.types.either settingAtom (lib.types.listOf settingAtom));
      default = {};
      example = {
        bold-is-bright = false;
        confirm-close-surface = false;
      };
      description = "Additional Ghostty settings merged into the configuration. A value is a string, a number, a boolean, or a list of those for a key that repeats.";
    };
  };
}
