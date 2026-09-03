# modules/system/stylix.nix
# System-wide theming with Stylix - Integration Pattern (system + user config)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.stylix;
  guiEnabled = cfg.gui.enable;
  themePath = ../../assets/themes/${cfg.polarity}/${cfg.scheme}.yaml;

  # BASE00..BASE0F session variables generated from the active scheme.
  baseColorVars =
    lib.mapAttrs'
    (name: lib.nameValuePair (lib.toUpper name))
    (lib.filterAttrs
      (name: value: builtins.isString value && builtins.match "base0[0-9A-Fa-f]" name != null)
      config.lib.stylix.colors);
in {
  options.othrys.system.stylix = {
    enable = lib.mkEnableOption "Stylix system-wide theming";

    polarity = lib.mkOption {
      type = lib.types.enum ["dark" "light"];
      default = "dark";
      description = "Color scheme polarity (dark or light).";
    };

    scheme = lib.mkOption {
      type = lib.types.str;
      default = "oxocarbon";
      description = "Theme name (must exist in assets/themes/{polarity}/{scheme}.yaml).";
    };

    wallpaper = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./wallpaper.png";
      description = ''
        Path to the desktop wallpaper image. Optional and identity-shaped, so
        no image ships with this library, so provide one from the consuming host.
        Null leaves the wallpaper unset; the color scheme still comes from
        `scheme`/`polarity`.
      '';
    };

    gui.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.othrys.desktop.graphical;
      defaultText = lib.literalExpression "config.othrys.desktop.graphical";
      description = ''
        Theme the graphical surface too: curated fonts, cursor, GTK, and
        per-user icon/cursor config. Off, Stylix still themes the console and
        Plymouth (the headless-relevant targets) without dragging the GUI
        font/cursor/GTK closure onto servers.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.pathExists themePath;
        message = "othrys.system.stylix: theme file ${toString themePath} not found. Check polarity (\"${cfg.polarity}\") and scheme (\"${cfg.scheme}\").";
      }
    ];

    stylix = {
      enable = true;

      # Stylix and Home Manager are independent flake inputs that may drift
      # between updates, so skip the version-match check rather than pin them.
      enableReleaseChecks = false;

      # Theme configuration
      base16Scheme = themePath;
      inherit (cfg) polarity;

      # Wallpaper
      image = cfg.wallpaper;

      # System fonts, GUI surface only. Console-only theming keeps the
      # upstream Stylix font defaults and skips the nerd-font closure.
      fonts = lib.mkIf guiEnabled {
        monospace = {
          package = pkgs.nerd-fonts.jetbrains-mono;
          name = "JetBrainsMono Nerd Font";
        };
        sansSerif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Sans";
        };
        serif = {
          package = pkgs.dejavu_fonts;
          name = "DejaVu Serif";
        };
        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
        sizes = {
          applications = 11;
          terminal = 15;
          desktop = 10;
          popups = 10;
        };
      };

      # Opacity settings
      opacity = {
        applications = 1.0;
        terminal = 0.95;
        desktop = 1.0;
        popups = 1.0;
      };

      # Cursor theme (GUI surface only)
      cursor = lib.mkIf guiEnabled {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 24;
      };

      # Application targets, where console/plymouth are the headless-relevant ones
      # and stay on, while GTK theming follows the GUI surface.
      targets = {
        console.enable = true;
        kmscon.enable = false;
        grub.enable = false;
        plymouth = {
          enable = true;
          logoAnimated = true;
        };
        gtk.enable = guiEnabled;
        gnome.enable = false;
      };
    };
    # Headless hosts still get the system-level Stylix targets (console,
    # plymouth). Only the per-user surface lands here.

    othrys.internal.homeConfig."system.stylix" = {
      # Stylix drives the cursor via home.pointerCursor.{name,package,size}.
      # Newer home-manager deprecates auto-enabling from those attrs, so opt in
      # explicitly to silence the deprecation warning. GUI surface only.
      home.pointerCursor.enable = lib.mkIf guiEnabled true;

      # Preserve legacy GTK4 theme behavior (stateVersion < 26.05).
      # Newer Stylix sets gtk.gtk4.theme = gtk.theme unconditionally, so force
      # null to keep GTK4 unthemed as before (resolves the null/not-null clash).
      gtk.gtk4.theme = lib.mkIf guiEnabled (lib.mkForce null);

      # Icon theme (follows polarity, GUI surface only)
      gtk.iconTheme = lib.mkIf guiEnabled {
        name =
          if cfg.polarity == "light"
          then "Papirus-Light"
          else "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };

      # Export Stylix colors as session variables. BASE00..0F are generated,
      # COLOR_* are semantic.
      home.sessionVariables =
        baseColorVars
        // (with config.lib.stylix.colors; {
          COLOR_BACKGROUND = base00;
          COLOR_FOREGROUND = base05;
          COLOR_SELECTION = base02;
          COLOR_COMMENT = base03;
          COLOR_CURSOR = base05;

          COLOR_BLACK = base00;
          COLOR_RED = base08;
          COLOR_GREEN = base0B;
          COLOR_YELLOW = base0A;
          COLOR_BLUE = base0D;
          COLOR_MAGENTA = base0E;
          COLOR_CYAN = base0C;
          COLOR_WHITE = base05;
          COLOR_ORANGE = base09;
          COLOR_BROWN = base0F;
        });

      # Color palette display utility
      home.packages = with pkgs; [
        (writeShellScriptBin "show-colors" ''
          #!/usr/bin/env bash

          print_color() {
            local name="$1"
            local hex="$2"
            local r=$((16#''${hex:0:2}))
            local g=$((16#''${hex:2:2}))
            local b=$((16#''${hex:4:2}))
            printf "\033[48;2;%d;%d;%dm  \033[0m  " "$r" "$g" "$b"
            printf "%-20s #%s   RGB(%3d, %3d, %3d)\n" "$name" "$hex" "$r" "$g" "$b"
          }

          echo "Current Stylix Color Palette"
          echo "──────────────────────────────────────────────────────────────────────"
          echo ""
          echo "Base16 Colors:"
          print_color "BASE00 (Background)" "$BASE00"
          print_color "BASE01 (Lighter BG)" "$BASE01"
          print_color "BASE02 (Selection)" "$BASE02"
          print_color "BASE03 (Comments)" "$BASE03"
          print_color "BASE04 (Dark FG)" "$BASE04"
          print_color "BASE05 (Foreground)" "$BASE05"
          print_color "BASE06 (Light FG)" "$BASE06"
          print_color "BASE07 (Light BG)" "$BASE07"
          echo ""
          print_color "BASE08 (Red)" "$BASE08"
          print_color "BASE09 (Orange)" "$BASE09"
          print_color "BASE0A (Yellow)" "$BASE0A"
          print_color "BASE0B (Green)" "$BASE0B"
          print_color "BASE0C (Cyan)" "$BASE0C"
          print_color "BASE0D (Blue)" "$BASE0D"
          print_color "BASE0E (Magenta)" "$BASE0E"
          print_color "BASE0F (Brown)" "$BASE0F"
          echo ""
          echo "Usage: echo \"\$BASE08\" for red hex code"
        '')
      ];
    };
  };
}
