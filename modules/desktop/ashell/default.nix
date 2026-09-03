# modules/desktop/ashell/default.nix
# Ashell status bar for Wayland compositors
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.desktop.ashell;
  hyprlandEnabled = config.othrys.desktop.compositors.hyprland.enable;
  niriEnabled = config.othrys.desktop.compositors.niri.enable;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  yubikeyEnabled = config.othrys.services.security.yubikey.enable;
  inherit (config.lib.stylix) colors;
  fontName = config.stylix.fonts.sansSerif.name;

  hlLua = import ../compositors/hyprland-lua.nix {inherit lib;};

  # Lock comes from the shared signal (one authority for every lock
  # consumer), while logout stays compositor-flavored, hyprland winning when both
  # compositors are enabled (one bar config per host).
  #
  # Under the Lua config provider `hyprctl dispatch` is a shorthand for
  # hl.dispatch(...), so the argument is a Lua expression, not a hyprlang
  # dispatcher name.
  lockCmd = config.othrys.desktop.lockCommand;
  logoutCmd =
    if hyprlandEnabled
    then "hyprctl dispatch 'hl.dsp.exit()'"
    else "niri msg action quit";

  configToml = ''
    position = "Top"
    layer = "Top"
    outputs = "All"

    # Unit system. ashell 0.9 derives ONE global unit for both weather and
    # system temps from `region` (no per-module override). en_US => Imperial
    # (°F, mph). Pinned explicitly so it doesn't drift with the login locale.
    region = "en_US"

    [modules]
    left = [["Custom:launcher", "Custom:clipboard", "Workspaces"]]
    center = ["WindowTitle"]
    right = ["MediaPlayer", "Tray", "SystemInfo", "Tempo", "Settings", "Notifications"]

    [appearance]
    font_name = "${fontName}"
    workspace_colors = ["#${colors.base0D}", "#${colors.base0E}", "#${colors.base0C}", "#${colors.base0B}", "#${colors.base09}"]
    special_workspace_colors = ["#${colors.base08}"]

    # Bar surface and opacity live under [appearance.bar]. They were
    # previously emitted as `style`/`opacity` directly under [appearance],
    # where ashell's Appearance struct has no such fields, and since every
    # field carries #[serde(default)] with no deny_unknown_fields, both keys
    # parsed cleanly and were discarded. The bar therefore rendered with the
    # BarSurface default (transparent, i.e. the per-group "islands" look) at
    # full opacity, regardless of what was written here.
    [appearance.bar]
    surface = "${cfg.bar.surface}"
    opacity = ${lib.strings.floatToString cfg.bar.opacity}

    [appearance.background_color]
    base = "#${colors.base00}"
    weakest = "#${colors.base00}"
    weaker = "#${colors.base01}"
    weak = "#${colors.base01}"
    neutral = "#${colors.base02}"
    strong = "#${colors.base02}"
    stronger = "#${colors.base03}"
    strongest = "#${colors.base04}"
    text = "#${colors.base05}"

    [appearance.primary_color]
    base = "#${colors.base0D}"
    text = "#${colors.base00}"

    [appearance.success_color]
    base = "#${colors.base0B}"
    text = "#${colors.base00}"

    [appearance.warning_color]
    base = "#${colors.base0A}"
    text = "#${colors.base00}"

    [appearance.danger_color]
    base = "#${colors.base08}"
    text = "#${colors.base00}"

    [appearance.text_color]
    base = "#${colors.base06}"

    [appearance.menu]
    opacity = 0.95
    backdrop = 0.3

    [workspaces]
    visibility_mode = "All"
    enable_workspace_filling = true

    [window_title]
    truncate_title_after_length = 80

    [system_info]
    interval = 5
    indicators = ["Cpu", "Memory", "Temperature"]

    [system_info.cpu]
    warn_threshold = 60
    alert_threshold = 80

    [system_info.memory]
    warn_threshold = 70
    alert_threshold = 85

    [system_info.temperature]
    # Thresholds are in the *display* unit, so °F here (Imperial). 140°F≈60°C,
    # 176°F≈80°C. (0.9 dropped the per-module `format`, and the unit is global now.)
    warn_threshold = 140
    alert_threshold = 176

    [tempo]
    clock_format = "%a %b %d  %I:%M:%S %p"
    weather_location = ${cfg.weatherLocation}
    weather_indicator = "IconAndTemperature"
    wind_speed_unit = "Mph"

    [settings]
    lock_cmd = "${lockCmd}"
    shutdown_cmd = "shutdown now"
    reboot_cmd = "systemctl reboot"
    suspend_cmd = "systemctl suspend"
    logout_cmd = "${logoutCmd}"
    remove_idle_btn = false
    remove_airplane_btn = true
    audio_sinks_more_cmd = "pavucontrol -t 3"
    audio_sources_more_cmd = "pavucontrol -t 4"
    peripheral_battery_format = "IconAndPercentage"
    peripheral_indicators = "All"
    indicators = ["IdleInhibitor", "PeripheralBattery", "Audio", "Microphone"]

    [notifications]
    format = "%I:%M %p"
    show_timestamps = true
    show_bodies = true
    grouped = true
    toast = true
    toast_position = "TopRight"
    toast_timeout = 5000
    toast_limit = 3
    toast_max_height = 150

    [media_player]
    max_title_length = 50
    indicator_format = "IconAndTitle"

    [[CustomModule]]
    name = "launcher"
    icon = "󱗼"
    command = "wofi --show drun"

    [[CustomModule]]
    name = "clipboard"
    icon = "󰅍"
    command = "cliphist list | wofi --dmenu | cliphist decode | wl-copy"
  '';
in {
  # ANCHOR: ashell-options
  options.othrys.desktop.ashell = {
    enable = lib.mkEnableOption "Ashell status bar";

    weatherLocation = lib.mkOption {
      type = lib.types.str;
      default = "{ Coordinates = [0.0, 0.0] }";
      example = "{ Coordinates = [40.7128, -74.0060] }";
      description = "ashell weather_location value, e.g. { Coordinates = [lat, lng] }.";
    };

    bar = {
      surface = lib.mkOption {
        type = lib.types.enum ["transparent" "solid"];
        default = "transparent";
        example = "solid";
        description = ''
          Where ashell paints the bar background. `transparent` leaves the bar
          see-through and paints each module group instead, giving the
          "islands" look; `solid` paints the whole bar as one continuous
          surface. Defaults to ashell's own default rather than a preference.
        '';
      };

      opacity = lib.mkOption {
        type = lib.types.float;
        default = 1.0;
        example = 0.92;
        description = ''
          Opacity of the bar surface. Below 1.0 ashell also asks the
          compositor for background blur (its blur mode defaults to `auto`,
          which engages exactly when opacity < 1); that needs
          `ext-background-effect-v1`, and is a no-op where unsupported.
        '';
      };
    };
  };
  # ANCHOR_END: ashell-options

  # The assertion lives in its own mkIf because the body interpolates Stylix colors
  # and fonts, so it must stay unevaluated when its dependencies are off or
  # the deep Stylix error preempts the assertion message.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = hyprlandEnabled || niriEnabled;
          message = "othrys.desktop.ashell requires a supported compositor: enable othrys.desktop.compositors.hyprland or othrys.desktop.compositors.niri.";
        }
      ];
    })
    (lib.mkIf (cfg.enable && (hyprlandEnabled || niriEnabled) && config.othrys.system.stylix.enable) {
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        users.${username}.directories = [
          ".config/ashell"
        ];
      };

      security.pam.services = lib.mkIf yubikeyEnabled (
        if hyprlandEnabled
        then {hyprlock.u2fAuth = true;}
        else {swaylock.u2fAuth = true;}
      );

      systemd.user.services.ashell = {
        description = "Ashell status bar.";
        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        serviceConfig = {
          ExecStart = "${inputs.ashell.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/ashell";
          Environment = "WGPU_BACKEND=vulkan";
          Slice = "session.slice";
          TimeoutStopSec = "5s";
          Restart = "on-failure";
        };
        wantedBy = ["graphical-session.target"];
      };

      othrys.internal.homeConfig."desktop.ashell" = {
        home.packages =
          [
            inputs.ashell.packages.${pkgs.stdenv.hostPlatform.system}.default
            pkgs.wofi
            pkgs.rofimoji
            pkgs.wtype
          ]
          # Hyprland-ecosystem tools on hyprland hosts, swaylock on niri
          # (niri-flake wires its pam entry). Idle management lives in
          # othrys.desktop.idle, not here.
          ++ lib.optionals hyprlandEnabled [
            pkgs.hyprlock
            pkgs.hyprpicker
          ]
          ++ lib.optional (!hyprlandEnabled) pkgs.swaylock;

        home.file.".config/ashell/config.toml".text = configToml;

        wayland.windowManager.hyprland.settings = lib.mkIf hyprlandEnabled {
          bind = map hlLua.mkBind [
            {
              key = "$mainMod + D";
              dispatcher = hlLua.execCmd "wofi --show drun";
            }
            {
              key = "$mainMod + SHIFT + D";
              dispatcher = hlLua.execCmd "wofi --show run";
            }
            {
              key = "$mainMod + E";
              dispatcher = hlLua.execCmd "rofimoji --selector wofi --clipboarder wl-copy --typer wtype --action type";
            }
            {
              key = "$mainMod + SHIFT + C";
              dispatcher = hlLua.execCmd "hyprpicker -a";
            }
          ];
        };

        # Same launcher chords on niri (hyprpicker is hyprland-only).
        programs.niri.settings.binds = lib.mkIf niriEnabled {
          "Mod+D".action.spawn = ["wofi" "--show" "drun"];
          "Mod+Shift+D".action.spawn = ["wofi" "--show" "run"];
          "Mod+E".action.spawn = ["rofimoji" "--selector" "wofi" "--clipboarder" "wl-copy" "--typer" "wtype" "--action" "type"];
        };
      };
    })
  ];
}
