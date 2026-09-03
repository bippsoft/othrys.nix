# modules/desktop/compositors/niri.nix
# Niri, a scrollable-tiling Wayland compositor. Config is generated through
# niri-flake's typed `programs.niri.settings` (build-time validated KDL);
# the option surface mirrors the hyprland module where concepts map (chords,
# terminal/browser, outputs, touchpad, screenshots) and is niri-native where
# they don't (columns scroll, so there is no workspace split to configure).
#
# Session: niri manages its own systemd session (`niri-session`), so no uwsm.
# Point othrys.desktop.login.sessionCommand at "niri-session".
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.othrys.desktop.compositors.niri;

  # A single action keybinding. The module defines the dispatcher and the
  # consumer picks the chord (or null to drop the bind entirely). Niri
  # resolves "Mod" to Super natively, so there is no mainMod indirection.
  bindOpt = default: action:
    lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      inherit default;
      description = "Key chord for ${action}; null disables the bind.";
    };

  mkBind = chord: action: lib.optionalAttrs (chord != null) {${chord} = action;};

  numberedWorkspaceBinds = lib.mergeAttrsList (
    map (n: {
      "Mod+${toString n}".action.focus-workspace = n;
      "Mod+Shift+${toString n}".action.move-column-to-workspace = n;
    }) (lib.range 1 9)
  );

  # Media keys work even on the lock screen.
  mediaBinds = {
    "XF86AudioRaiseVolume" = {
      allow-when-locked = true;
      action.spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05+"];
    };
    "XF86AudioLowerVolume" = {
      allow-when-locked = true;
      action.spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.05-"];
    };
    "XF86AudioMute" = {
      allow-when-locked = true;
      action.spawn = ["wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"];
    };
    "XF86AudioPlay" = {
      allow-when-locked = true;
      action.spawn = ["playerctl" "play-pause"];
    };
    "XF86AudioPause" = {
      allow-when-locked = true;
      action.spawn = ["playerctl" "play-pause"];
    };
  };

  binds =
    mkBind cfg.binds.focusLeft {action.focus-column-left = [];}
    // mkBind cfg.binds.focusRight {action.focus-column-right = [];}
    // mkBind cfg.binds.focusDown {action.focus-window-down = [];}
    // mkBind cfg.binds.focusUp {action.focus-window-up = [];}
    // mkBind cfg.binds.moveLeft {action.move-column-left = [];}
    // mkBind cfg.binds.moveRight {action.move-column-right = [];}
    // mkBind cfg.binds.moveDown {action.move-window-down = [];}
    // mkBind cfg.binds.moveUp {action.move-window-up = [];}
    // mkBind cfg.binds.killActive {action.close-window = [];}
    // mkBind cfg.binds.terminal {action.spawn = cfg.terminal;}
    // mkBind cfg.binds.browser {action.spawn = cfg.browser;}
    // mkBind cfg.binds.fullscreen {action.fullscreen-window = [];}
    // mkBind cfg.binds.maximizeColumn {action.maximize-column = [];}
    // mkBind cfg.binds.toggleFloating {action.toggle-window-floating = [];}
    // mkBind cfg.binds.overview {action.toggle-overview = [];}
    // mkBind cfg.binds.exit {action.quit = [];}
    // mkBind cfg.binds.workspacePrev {action.focus-workspace-up = [];}
    // mkBind cfg.binds.workspaceNext {action.focus-workspace-down = [];}
    // mkBind cfg.binds.screenshot {action.screenshot = [];}
    // mkBind cfg.binds.screenshotScreen {action.screenshot-screen = [];}
    // mkBind cfg.binds.screenshotWindow {action.screenshot-window = [];}
    // lib.optionalAttrs cfg.numberedWorkspaceBinds numberedWorkspaceBinds
    // mediaBinds
    // cfg.extraBinds;

  generatedSettings =
    {
      inherit binds;
      inherit (cfg) outputs;

      # Server-side decorations fit the tiling aesthetic, though Electron apps run
      # native Wayland. Both overridable through `settings` (with mkForce for
      # already-set leaves).
      prefer-no-csd = true;
      environment."NIXOS_OZONE_WL" = "1";

      screenshot-path = "${cfg.screenshots.directory}/Screenshot from %Y-%m-%d %H-%M-%S.png";
    }
    // lib.optionalAttrs cfg.touchpad.enable {
      input.touchpad = {
        tap = true;
        natural-scroll = true;
      };
    };
in {
  # niri-flake is self-contained, since its NixOS module is
  # imported here directly, so consumers need no extra upstream import.
  imports = [inputs.niri.nixosModules.niri];

  # ANCHOR: niri-options
  options.othrys.desktop.compositors.niri = {
    enable = lib.mkEnableOption "Niri scrollable-tiling Wayland compositor";

    outputs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      example = lib.literalExpression ''
        {
          "DP-1" = {
            mode = {
              width = 1920;
              height = 1080;
              refresh = 144.0;
            };
            position = {
              x = 0;
              y = 0;
            };
          };
        }
      '';
      description = "Monitor configuration (programs.niri.settings.outputs). Empty lets niri auto-configure.";
    };

    terminal = lib.mkOption {
      type = lib.types.str;
      default = "kitty";
      description = "Terminal emulator the terminal bind spawns.";
    };

    browser = lib.mkOption {
      type = lib.types.str;
      default = "firefox";
      description = "Browser the browser bind spawns.";
    };

    screenshots.directory = lib.mkOption {
      type = lib.types.str;
      default = "~/Pictures/Screenshots";
      description = "Directory niri's built-in screenshot UI saves into.";
    };

    # Curated actions with configurable chords, the hyprland pattern. Same
    # chords where the concept maps (muscle-memory parity), and niri-native
    # actions (columns, overview) where it doesn't.
    binds = {
      focusLeft = bindOpt "Mod+H" "focus column left";
      focusRight = bindOpt "Mod+L" "focus column right";
      focusDown = bindOpt "Mod+J" "focus window down";
      focusUp = bindOpt "Mod+K" "focus window up";

      moveLeft = bindOpt "Mod+Shift+H" "move column left";
      moveRight = bindOpt "Mod+Shift+L" "move column right";
      moveDown = bindOpt "Mod+Shift+J" "move window down";
      moveUp = bindOpt "Mod+Shift+K" "move window up";

      killActive = bindOpt "Mod+Q" "close the active window";
      terminal = bindOpt "Mod+Return" "launch the terminal";
      browser = bindOpt "Mod+F" "launch the browser";

      fullscreen = bindOpt "Mod+M" "toggle fullscreen";
      maximizeColumn = bindOpt "Mod+P" "maximize the column";
      toggleFloating = bindOpt "Mod+V" "toggle floating";
      overview = bindOpt "Mod+S" "toggle the overview";
      exit = bindOpt "Mod+Shift+E" "quit niri";

      workspacePrev = bindOpt "Mod+Ctrl+Left" "previous workspace";
      workspaceNext = bindOpt "Mod+Ctrl+Right" "next workspace";

      screenshot = bindOpt "Print" "open the interactive screenshot UI";
      screenshotScreen = bindOpt "Mod+Print" "screenshot the full screen";
      screenshotWindow = bindOpt "Mod+Shift+Print" "screenshot the focused window";
    };

    numberedWorkspaceBinds = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate Mod+1..9 workspace focus and Mod+Shift+1..9 move binds.";
    };

    extraBinds = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      example = lib.literalExpression ''
        {
          "Mod+T".action.spawn = "thunderbird";
        }
      '';
      description = "Additional binds in programs.niri.settings.binds format, merged over the generated set.";
    };

    touchpad = {
      enable = lib.mkEnableOption "touchpad tuning (tap-to-click, natural scroll) for laptops";
    };

    xwayland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install xwayland-satellite so X11 applications run (niri detects and manages it automatically).";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra programs.niri.settings, merged over the generated config (use lib.mkForce to override an already-set leaf).";
    };
  };
  # ANCHOR_END: niri-options

  # The assertion lives in its own mkIf because the stylix target (auto-imported by
  # niri-flake) themes borders/cursor from the palette, so the body stays
  # unevaluated when stylix is off and the assertion message surfaces.
  config = lib.mkMerge [
    {
      # niri-flake's auto-cache activates on IMPORT, not enable, and would
      # add its substituter for every consumer. The cache is instead added in
      # othrys.system.nix, gated on this module's enable, mirroring the
      # hyprland cache.
      niri-flake.cache.enable = false;

      # nixpkgs' niri rather than niri-flake's default build, since the flake's builder
      # pins libdisplay-info 0.2, which nixpkgs removed (2026-08), so its
      # package no longer evaluates against our nixpkgs pin. This override is
      # unconditional (not enable-gated) because niri-flake injects its
      # home-manager config module into every HM user on import, and that
      # module dereferences the package even with niri disabled. mkDefault so
      # a consumer can point back at a niri-flake build (the niri.cachix
      # substituter in othrys.system.nix still covers that).
      programs.niri.package = lib.mkDefault pkgs.niri;

      # niri-flake also injects its Stylix HM target into every home-manager
      # user on import. That module reads the HM-scoped `config.stylix.enable`,
      # which only exists when Stylix manages the user. On stylix-disabled
      # hosts it would crash eval. Declare a minimal `stylix.enable = false`
      # there so the target's guard short-circuits. When othrys stylix is on,
      # the real Stylix HM module provides the option instead.
      home-manager.sharedModules = lib.optionals (!config.othrys.system.stylix.enable) [
        {
          options.stylix.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            internal = true;
            description = "Shim for niri-flake's injected Stylix target on hosts without Stylix home-manager config.";
          };
        }
      ];
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.othrys.system.stylix.enable;
          message = "othrys.desktop.compositors.niri requires othrys.system.stylix.enable = true (compositor theming reads the Stylix palette).";
        }
      ];

      # This host runs a graphical session, and modules key GUI behavior on this.
      othrys.desktop.graphical = true;
    })
    (lib.mkIf (cfg.enable && config.othrys.system.stylix.enable) {
      programs.niri.enable = true;

      environment.systemPackages =
        [
          pkgs.wl-clipboard
          pkgs.playerctl
        ]
        ++ lib.optional cfg.xwayland.enable pkgs.xwayland-satellite;

      othrys.internal.homeConfig."desktop.compositors.niri" = {
        programs.niri.settings = lib.mkMerge [
          generatedSettings
          cfg.settings
        ];
      };
    })
  ];
}
