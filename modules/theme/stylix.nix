# modules/theme/stylix.nix
# Stylix adapter, which configures Stylix from othrys.theme and fills the theme back from it
#
# Exported as nixosModules.stylix and left out of nixosModules.default, so a
# host imports it together with the Stylix module or imports neither. It is
# the only file in this tree that writes into the `stylix` option namespace
# or reads `config.lib.stylix`. Every other module reads othrys.theme.
#
# Colour flows one way for a named scheme and the other way for a generated
# one. A named scheme is read from othrys.theme.schemes and handed to Stylix.
# With `othrys.theme.scheme = "wallpaper"` Stylix generates the palette from
# the wallpaper and this module copies it into othrys.theme.palette. The
# scheme handed to Stylix is therefore read from the scheme table and never
# from othrys.theme.palette, which would make the generated case depend on
# itself.
{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.stylix;
  theme = config.othrys.theme;
  guiEnabled = cfg.gui.enable;

  fromWallpaper = theme.scheme == "wallpaper";
  schemePalette =
    if theme.scheme == null || fromWallpaper
    then null
    else theme.schemes.${theme.scheme}.${theme.polarity} or null;

  # Stylix throws while its colours are being computed when it has neither a
  # scheme nor an image, and that error arrives before any assertion is
  # reported. The body below is skipped in that case, so the assertions are
  # what the host sees.
  configured =
    if fromWallpaper
    then theme.wallpaper.source != null
    else schemePalette != null;

  # The sixteen base16 colours Stylix computed, with the eight base24 ones
  # where it has them, in the shape of othrys.theme.palette. The name is
  # matched first, so no other attribute of the colour set is evaluated.
  stylixPalette =
    lib.filterAttrs
    (name: value: builtins.match "base(0[0-9A-F]|1[0-7])" name != null && builtins.isString value)
    config.lib.stylix.colors;

  # BASE00..BASE0F session variables generated from the active scheme.
  baseColorVars =
    lib.mapAttrs'
    (name: lib.nameValuePair (lib.toUpper name))
    (lib.filterAttrs
      (name: value: builtins.match "base0[0-9A-Fa-f]" name != null && builtins.isString value)
      config.lib.stylix.colors);
in {
  imports = [
    (lib.mkRenamedOptionModule ["othrys" "system" "stylix" "scheme"] ["othrys" "theme" "scheme"])
    (lib.mkRenamedOptionModule ["othrys" "system" "stylix" "polarity"] ["othrys" "theme" "polarity"])
    (lib.mkRenamedOptionModule ["othrys" "system" "stylix" "wallpaper"] ["othrys" "theme" "wallpaper" "source"])
  ];

  options.othrys.system.stylix = {
    enable = lib.mkEnableOption "Stylix system-wide theming, configured from `othrys.theme`";

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

  config = lib.mkMerge [
    # niri-flake adds its Stylix target to every Home Manager user on a host
    # that declares the `stylix` option namespace, and that target reads the
    # Home Manager option `stylix.enable`. Stylix declares the option there
    # only while it is enabled, so a host that imports both and leaves Stylix
    # off would fail to evaluate. A minimal `stylix.enable = false` is
    # declared for that case, and the target's guard then short-circuits.
    # With Stylix on, its own Home Manager module provides the option.
    (lib.optionalAttrs (options ? home-manager) {
      home-manager.sharedModules = lib.optionals (!config.stylix.enable) [
        {
          options.stylix.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            internal = true;
            description = "Shim for niri-flake's injected Stylix target on hosts without Stylix home-manager config.";
          };
        }
      ];
    })

    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !fromWallpaper || theme.wallpaper.source != null;
          message = "othrys.theme.scheme = \"wallpaper\" derives the palette from the wallpaper, and othrys.theme.wallpaper.source is not set.";
        }
        {
          assertion = fromWallpaper || theme.scheme != null;
          message = "othrys.system.stylix.enable needs a scheme, since Stylix cannot run without a palette. Set othrys.theme.scheme to a name in othrys.theme.schemes or to \"wallpaper\".";
        }
      ];

      othrys.internal.wallpaperPalette = true;
    })

    (lib.mkIf (cfg.enable && configured) {
      # Every taste value is a default, so a host changes one without mkForce.
      # The GUI surface is guarded once, at the attrset level.
      stylix = lib.mkMerge [
        {
          enable = true;

          # Stylix and Home Manager are independent flake inputs that may drift
          # between updates, so skip the version-match check rather than pin them.
          enableReleaseChecks = false;

          # A named scheme is handed over as an attribute set. With no
          # definition here Stylix generates the palette from the image,
          # which is the wallpaper case.
          base16Scheme = lib.mkIf (!fromWallpaper) schemePalette;
          inherit (theme) polarity;

          # Wallpaper
          image = theme.wallpaper.source;

          # Opacity settings
          opacity = {
            applications = lib.mkDefault 1.0;
            terminal = lib.mkDefault 0.95;
            desktop = lib.mkDefault 1.0;
            popups = lib.mkDefault 1.0;
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
        }
        (lib.mkIf guiEnabled {
          # System fonts, GUI surface only. Console-only theming keeps the
          # upstream Stylix font defaults and skips the nerd-font closure.
          fonts = {
            monospace = {
              package = lib.mkDefault pkgs.nerd-fonts.jetbrains-mono;
              name = lib.mkDefault "JetBrainsMono Nerd Font";
            };
            sansSerif = {
              package = lib.mkDefault pkgs.dejavu_fonts;
              name = lib.mkDefault "DejaVu Sans";
            };
            serif = {
              package = lib.mkDefault pkgs.dejavu_fonts;
              name = lib.mkDefault "DejaVu Serif";
            };
            emoji = {
              package = lib.mkDefault pkgs.noto-fonts-color-emoji;
              name = lib.mkDefault "Noto Color Emoji";
            };
            sizes = {
              applications = lib.mkDefault 11;
              terminal = lib.mkDefault 15;
              desktop = lib.mkDefault 10;
              popups = lib.mkDefault 10;
            };
          };

          # Cursor theme
          cursor = {
            package = lib.mkDefault pkgs.bibata-cursors;
            name = lib.mkDefault "Bibata-Modern-Classic";
            size = lib.mkDefault 24;
          };
        })
      ];

      # The fonts and opacity Stylix ends up with become the theme's, so the
      # bar and the compositor read the font Stylix gives everything else.
      # Each is a default, and a host that sets the othrys.theme option wins.
      othrys.theme = {
        palette = lib.mkIf fromWallpaper (lib.mkDefault stylixPalette);

        fonts = {
          sansSerif = lib.mkDefault {inherit (config.stylix.fonts.sansSerif) name package;};
          monospace = lib.mkDefault {inherit (config.stylix.fonts.monospace) name package;};
        };

        opacity = lib.mkDefault {inherit (config.stylix.opacity) terminal applications desktop popups;};
      };

      # Headless hosts still get the system-level Stylix targets (console,
      # plymouth). Only the per-user surface lands here.

      # The registry holds one raw value per key, so the parts are joined as
      # plain attribute sets and not with mkMerge.
      othrys.internal.homeConfig."system.stylix" = builtins.foldl' lib.recursiveUpdate {} [
        (lib.optionalAttrs guiEnabled {
          # Stylix drives the cursor via home.pointerCursor.{name,package,size}.
          # Newer home-manager deprecates auto-enabling from those attrs, so opt in
          # explicitly to silence the deprecation warning.
          home.pointerCursor.enable = true;

          # Preserve legacy GTK4 theme behavior (stateVersion < 26.05).
          # Newer Stylix sets gtk.gtk4.theme = gtk.theme unconditionally, so force
          # null to keep GTK4 unthemed as before (resolves the null/not-null clash).
          gtk.gtk4.theme = lib.mkForce null;

          # Icon theme, following the polarity
          gtk.iconTheme = {
            name = lib.mkDefault (
              if theme.polarity == "light"
              then "Papirus-Light"
              else "Papirus-Dark"
            );
            package = lib.mkDefault pkgs.papirus-icon-theme;
          };
        })

        # Stylix's own browser theme for the Floorp profile othrys creates.
        # The app tree is absent when this file is imported without it, so
        # the read falls back to off.
        (lib.optionalAttrs (config.othrys.apps.floorp.enable or false) {
          stylix.targets.floorp = {
            enable = true;
            profileNames = ["default"];
          };
        })

        {
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
        }
      ];
    })
  ];
}
