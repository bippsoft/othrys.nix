# modules/desktop/noctalia.nix
# Noctalia, a native Wayland desktop shell (bar, launcher, control center,
# notifications, lock screen, wallpaper, clipboard, OSD in one layer, with no
# Qt/GTK). Configured through upstream's home-manager module, where declarative
# defaults land in a build-time-validated config.toml, and the GUI's runtime
# overrides layer on top in ~/.local/state/noctalia (persisted under
# impermanence), so nix-declared config and in-shell settings coexist.
#
# Theming defaults to a custom palette generated from the Stylix base16
# scheme (one theming authority, and noctalia synthesizes terminal colors from
# the tokens), while theme.source escapes to noctalia's builtin/wallpaper/
# community engines.
#
# Exclusive with ashell, since a host runs one shell layer.
{
  config,
  lib,
  inputs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.desktop.noctalia;
  hyprlandEnabled = config.othrys.desktop.compositors.hyprland.enable;
  niriEnabled = config.othrys.desktop.compositors.niri.enable;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # A single action keybinding. The module defines the IPC dispatcher and the
  # consumer picks the chord (or null to drop the bind entirely). Chords use
  # niri syntax ("Mod+Shift+V") and are translated for hyprland.
  bindOpt = default: action:
    lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      inherit default;
      description = "Key chord for ${action}; null disables the bind.";
    };

  hlLua = import ./compositors/hyprland-lua.nix {inherit lib;};

  toHyprChord = chord: let
    parts = lib.splitString "+" chord;
    key = lib.last parts;
    mods = map (m:
      if m == "Mod"
      then "$mainMod"
      else lib.toUpper m) (lib.init parts);
  in
    lib.concatStringsSep " + " (mods ++ [key]);

  # IPC commands as registered in noctalia's dispatcher (panel-toggle <id>,
  # session lock), and the argv form is shared by both compositors.
  bindActions =
    lib.optional (cfg.binds.launcher != null) {
      chord = cfg.binds.launcher;
      argv = ["noctalia" "msg" "panel-toggle" "launcher"];
    }
    ++ lib.optional (cfg.binds.clipboard != null) {
      chord = cfg.binds.clipboard;
      argv = ["noctalia" "msg" "panel-toggle" "clipboard"];
    }
    ++ lib.optional (cfg.binds.session != null) {
      chord = cfg.binds.session;
      argv = ["noctalia" "msg" "panel-toggle" "session"];
    }
    ++ lib.optional (cfg.binds.lock != null) {
      chord = cfg.binds.lock;
      argv = ["noctalia" "msg" "session" "lock"];
    };

  hyprlandBinds = map (b:
    hlLua.mkBind {
      key = toHyprChord b.chord;
      dispatcher = hlLua.execCmd (lib.concatStringsSep " " b.argv);
    })
  bindActions;
  niriBinds = lib.mergeAttrsList (map (b: {${b.chord}.action.spawn = b.argv;}) bindActions);

  # source = "stylix" delegates the palette entirely to Stylix's own noctalia
  # target (stylix.targets.noctalia), which writes theme.source/custom_palette
  # and a full palette incl. terminal colors, with no hand-rolled bridge to drift.
  stylixThemed = cfg.theme.source == "stylix";

  generatedSettings = {
    # font_family, theme.mode, popup/dock opacities, and the default wallpaper
    # come from Stylix's noctalia target when source = "stylix"; this module
    # only fills them for noctalia's own theming engines.
    shell =
      {
        clipboard_enabled = cfg.clipboard.enable;
        clipboard_history_max_entries = cfg.clipboard.historyMaxEntries;

        launcher = {
          sort_by_usage = cfg.launcher.sortByUsage;
          inherit (cfg.launcher) compact;
          app_grid = cfg.launcher.appGrid;
          provider_prefix = cfg.launcher.providerPrefix;
        };
      }
      // lib.optionalAttrs (!stylixThemed) {
        font_family = config.stylix.fonts.sansSerif.name;
      };

    bar.main = {
      inherit (cfg.bar) position thickness radius;
      background_opacity = cfg.bar.backgroundOpacity;
      auto_hide = cfg.bar.autoHide;
      inherit (cfg.bar.widgets) start center end;
    };

    # With source = "stylix", the source/palette/mode keys come from the
    # Stylix target instead, and only pure_black_dark is always ours.
    theme =
      {
        pure_black_dark = cfg.theme.pureBlackDark;
      }
      // lib.optionalAttrs (!stylixThemed) {
        inherit (cfg.theme) mode;
      }
      // lib.optionalAttrs (cfg.theme.source == "builtin") {
        source = "builtin";
        inherit (cfg.theme) builtin;
      }
      // lib.optionalAttrs (cfg.theme.source == "community") {
        source = "community";
        community_palette = cfg.theme.communityPalette;
      }
      // lib.optionalAttrs (cfg.theme.source == "wallpaper") {
        source = "wallpaper";
        wallpaper_scheme = cfg.theme.wallpaperScheme;
      };

    lockscreen = {
      enabled = cfg.lockscreen.enable;
      blurred_desktop = cfg.lockscreen.blurredDesktop;
      blur_intensity = cfg.lockscreen.blurIntensity;
      tint_intensity = cfg.lockscreen.tintIntensity;
    };

    # Toast/dock opacity comes from Stylix (stylix.opacity.popups/desktop)
    # when stylix-themed, and only the layer is a noctalia-specific choice.
    notification = {
      inherit (cfg.notifications) layer;
    };

    wallpaper = {
      enabled = cfg.wallpaper.enable;
      inherit (cfg.wallpaper) directory;
      fill_mode = cfg.wallpaper.fillMode;
      transition_duration = cfg.wallpaper.transitionDuration;
    };

    dock = {
      enabled = cfg.dock.enable;
      inherit (cfg.dock) position;
      icon_size = cfg.dock.iconSize;
    };

    weather = {
      enabled = cfg.weather.enable;
      inherit (cfg.weather) unit;
    };

    location = {
      auto_locate = cfg.location.autoLocate;
      inherit (cfg.location) address;
    };
  };
in {
  # ANCHOR: noctalia-options
  options.othrys.desktop.noctalia = {
    enable = lib.mkEnableOption "Noctalia Wayland desktop shell (bar, launcher, notifications, lock screen, wallpaper, clipboard)";

    bar = {
      position = lib.mkOption {
        type = lib.types.enum ["top" "bottom" "left" "right"];
        default = "top";
        description = "Bar edge.";
      };
      thickness = lib.mkOption {
        type = lib.types.ints.positive;
        default = 34;
        description = "Bar thickness in pixels.";
      };
      backgroundOpacity = lib.mkOption {
        type = lib.types.float;
        default = 1.0;
        description = "Bar background opacity.";
      };
      radius = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 12;
        description = "Bar corner radius.";
      };
      autoHide = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Hide the bar until the edge is hovered.";
      };
      widgets = {
        start = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["launcher" "wallpaper" "workspaces"];
          description = "Widgets at the start of the bar.";
        };
        center = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["clock"];
          description = "Widgets at the center of the bar.";
        };
        end = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["media" "tray" "notifications" "clipboard" "network" "bluetooth" "volume" "brightness" "battery" "control-center" "session"];
          description = "Widgets at the end of the bar.";
        };
      };
    };

    theme = {
      source = lib.mkOption {
        type = lib.types.enum ["stylix" "builtin" "wallpaper" "community"];
        default = "stylix";
        description = "Palette source: \"stylix\" generates a custom palette from the Stylix base16 scheme (the repo's single theming authority); the others use noctalia's own engines.";
      };
      mode = lib.mkOption {
        type = lib.types.enum ["dark" "light" "auto"];
        default = config.othrys.system.stylix.polarity;
        defaultText = lib.literalExpression "config.othrys.system.stylix.polarity";
        description = "Shell light/dark mode for noctalia's own theming engines; with source = \"stylix\" the mode follows the Stylix polarity via its target.";
      };
      builtin = lib.mkOption {
        type = lib.types.str;
        default = "Noctalia";
        description = "Builtin palette name (used when source = \"builtin\").";
      };
      communityPalette = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Community palette name (used when source = \"community\").";
      };
      wallpaperScheme = lib.mkOption {
        type = lib.types.str;
        default = "m3-tonal-spot";
        description = "Material scheme for wallpaper-generated palettes (used when source = \"wallpaper\").";
      };
      pureBlackDark = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Anchor dark surfaces to true black (OLED).";
      };
    };

    launcher = {
      sortByUsage = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Sort apps by usage frequency.";
      };
      compact = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Smaller icons and tighter result rows.";
      };
      appGrid = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Icon grid view when results are apps only.";
      };
      providerPrefix = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "Prefix character for launcher provider trigger words.";
      };
    };

    lockscreen = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable noctalia's session lock screen.";
      };
      blurredDesktop = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use a blurred desktop snapshot as the lock background (requires wlr-screencopy).";
      };
      blurIntensity = lib.mkOption {
        type = lib.types.float;
        default = 0.5;
        description = "Lock background blur (0.0-1.0).";
      };
      tintIntensity = lib.mkOption {
        type = lib.types.float;
        default = 0.3;
        description = "Surface-color tint over the lock background.";
      };
    };

    notifications = {
      layer = lib.mkOption {
        type = lib.types.enum ["top" "overlay"];
        default = "top";
        description = "Layer notification toasts render on (opacity follows stylix.opacity when stylix-themed).";
      };
    };

    wallpaper = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Let noctalia manage the wallpaper.";
      };
      directory = lib.mkOption {
        type = lib.types.str;
        default = "~/Pictures/Wallpapers";
        description = "Wallpaper directory the picker browses.";
      };
      fillMode = lib.mkOption {
        type = lib.types.enum ["center" "crop" "fit" "stretch" "repeat" "span"];
        default = "crop";
        description = "Wallpaper fill mode.";
      };
      transitionDuration = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 1500;
        description = "Wallpaper transition duration in milliseconds.";
      };
    };

    clipboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Clipboard panel, history, and compositor clipboard hooks.";
      };
      historyMaxEntries = lib.mkOption {
        type = lib.types.ints.positive;
        default = 100;
        description = "Unpinned clipboard history cap.";
      };
    };

    dock = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the dock.";
      };
      position = lib.mkOption {
        type = lib.types.enum ["top" "bottom" "left" "right"];
        default = "bottom";
        description = "Dock edge.";
      };
      iconSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 48;
        description = "Dock icon size in pixels.";
      };
    };

    weather = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Weather widget/panel (uses the coordinates from `location`).";
      };
      unit = lib.mkOption {
        type = lib.types.enum ["celsius" "fahrenheit"];
        default = "celsius";
        description = "Temperature unit.";
      };
    };

    location = {
      autoLocate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Resolve coordinates from IP (network lookup).";
      };
      address = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Toronto, ON";
        description = "Location address, geocoded for weather/night-light. Identity-shaped, set from the consuming host.";
      };
    };

    # Curated chords for noctalia's surfaces, written into whichever
    # compositor is enabled (niri syntax, translated for hyprland).
    binds = {
      launcher = bindOpt "Mod+D" "toggle the launcher";
      clipboard = bindOpt "Mod+Shift+V" "toggle the clipboard panel";
      session = bindOpt "Mod+X" "toggle the session panel";
      lock = bindOpt "Mod+Ctrl+L" "lock the screen";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra noctalia config.toml settings, deep-merged over (and overriding) the generated config. Validated at build time by upstream's module.";
    };

    customPalettes = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Additional custom palettes written to noctalia/palettes/<name>.json.";
    };
  };
  # ANCHOR_END: noctalia-options

  # The assertion lives in its own mkIf because the body interpolates Stylix colors
  # and fonts, so it must stay unevaluated when stylix is off or the deep
  # Stylix error preempts the assertion message.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.othrys.desktop.graphical;
          message = "othrys.desktop.noctalia requires a graphical session: enable a compositor module (or set othrys.desktop.graphical for an unmanaged one).";
        }
        {
          assertion = !config.othrys.desktop.ashell.enable;
          message = "othrys.desktop.noctalia and othrys.desktop.ashell are exclusive shell layers (two bars/notification daemons would fight). Enable one.";
        }
        {
          assertion = config.othrys.system.stylix.enable;
          message = "othrys.desktop.noctalia requires othrys.system.stylix.enable = true (shell fonts and the default palette read the Stylix scheme).";
        }
      ];

      # Noctalia owns the lock screen, and every lock consumer dispatches to it.
      othrys.desktop.lockCommand = "noctalia msg session lock";
    })
    (lib.mkIf (cfg.enable && config.othrys.system.stylix.enable) {
      # The GUI's runtime overrides (settings.toml) live in the state dir, so
      # persisting them keeps in-shell tweaks across the root wipe.
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        users.${username}.directories = [
          ".local/state/noctalia"
        ];
      };

      home-manager.users.${username} = {
        imports = [inputs.noctalia.homeModules.default];

        programs.noctalia = {
          enable = true;
          systemd.enable = true;
          settings = lib.recursiveUpdate generatedSettings cfg.settings;
          inherit (cfg) customPalettes;
        };

        # Stylix's noctalia target provides the palette for source = "stylix";
        # for noctalia's own engines it must stand down or its
        # theme.source = "custom" write conflicts.
        stylix.targets.noctalia.enable = stylixThemed;

        wayland.windowManager.hyprland.settings = lib.mkIf hyprlandEnabled {
          bind = hyprlandBinds;
        };

        programs.niri.settings.binds = lib.mkIf niriEnabled niriBinds;
      };
    })
  ];
}
