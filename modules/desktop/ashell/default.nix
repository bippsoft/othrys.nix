# modules/desktop/ashell/default.nix
# Ashell status bar for Wayland compositors
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.othrys.desktop.ashell;
  hyprlandEnabled = config.othrys.desktop.compositors.hyprland.enable;
  niriEnabled = config.othrys.desktop.compositors.niri.enable;
  theme = config.othrys.theme;
  themed = theme.palette != null;
  # Read only where `themed` holds. Null without a palette.
  colors = theme.colors.withHashtag;
  font = theme.fonts.sansSerif;

  hlLua = import ../compositors/hyprland-lua.nix {inherit lib;};
  session = import ../session.nix {inherit config pkgs;};

  # Lock comes from the shared signal (one authority for every lock
  # consumer), while logout follows the running compositor, since a host
  # with both compositors has one bar config for the two sessions.
  #
  # Under the Lua config provider `hyprctl dispatch` is a shorthand for
  # hl.dispatch(...), so the argument is a Lua expression, not a hyprlang
  # dispatcher name.
  lockCmd = config.othrys.desktop.lockCommand;

  # What a laptop adds to the bar. Each entry is listed only when the host runs
  # the service the indicator reads, so nothing sits in the bar empty.
  laptop = config.othrys.hardware.laptop.enable;
  # The desktop list is the one the bar always had, in its old order.
  defaultIndicators =
    if !laptop
    then ["IdleInhibitor" "PeripheralBattery" "Audio" "Microphone"]
    else
      ["IdleInhibitor"]
      ++ lib.optional config.services.power-profiles-daemon.enable "PowerProfile"
      ++ ["Audio" "Microphone" "Brightness" "Network"]
      ++ lib.optional config.hardware.bluetooth.enable "Bluetooth"
      ++ ["PeripheralBattery" "Battery"];
  logoutCmd = session.bySession "othrys-logout" {
    hyprland = "hyprctl dispatch 'hl.dsp.exit()'";
    niri = "niri msg action quit";
  };

  # ashell reads weather_location as a tagged value, a table with the one key
  # City over a string or the one key Coordinates over a pair of floats. Both
  # are written through toJSON, whose strings and floats are valid TOML, and
  # an integer is made a float first so the pair is always two floats.
  weatherLocationToml = location:
    if builtins.isString location
    then "{ City = ${builtins.toJSON location} }"
    else "{ Coordinates = [${builtins.toJSON (location.latitude * 1.0)}, ${builtins.toJSON (location.longitude * 1.0)}] }";

  cliphist = lib.getExe pkgs.cliphist;

  leftModules = ["Custom:launcher"] ++ lib.optional cfg.clipboard.enable "Custom:clipboard" ++ ["Workspaces"];
  tomlList = lib.concatMapStringsSep ", " (name: "\"${name}\"");

  configToml = ''
    position = "Top"
    layer = "Top"
    outputs = "All"

    # Unit system. ashell 0.9 derives ONE global unit for both weather and
    # system temps from `region` (no per-module override). en_US => Imperial
    # (°F, mph). Pinned explicitly so it doesn't drift with the login locale.
    region = "en_US"

    [modules]
    left = [[${tomlList leftModules}]]
    center = ["WindowTitle"]
    right = ["MediaPlayer", "Tray", "SystemInfo", "Tempo", "Settings", "Notifications"]

    # The font and every colour below come from othrys.theme. A key whose
    # theme value is null is left out, and ashell then uses its own default.
    [appearance]
    ${lib.optionalString (font != null) "font_name = \"${font.name}\""}
    ${lib.optionalString themed ''
      workspace_colors = ["${colors.base0D}", "${colors.base0E}", "${colors.base0C}", "${colors.base0B}", "${colors.base09}"]
      special_workspace_colors = ["${colors.base08}"]
    ''}

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

    ${lib.optionalString themed ''
      [appearance.background_color]
      base = "${colors.base00}"
      weakest = "${colors.base00}"
      weaker = "${colors.base01}"
      weak = "${colors.base01}"
      neutral = "${colors.base02}"
      strong = "${colors.base02}"
      stronger = "${colors.base03}"
      strongest = "${colors.base04}"
      text = "${colors.base05}"

      [appearance.primary_color]
      base = "${colors.base0D}"
      text = "${colors.base00}"

      [appearance.success_color]
      base = "${colors.base0B}"
      text = "${colors.base00}"

      [appearance.warning_color]
      base = "${colors.base0A}"
      text = "${colors.base00}"

      [appearance.danger_color]
      base = "${colors.base08}"
      text = "${colors.base00}"

      [appearance.text_color]
      base = "${colors.base06}"
    ''}

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
    clock_format = "${cfg.clockFormat}"
    ${lib.optionalString (cfg.weatherLocation != null) "weather_location = ${weatherLocationToml cfg.weatherLocation}"}
    weather_indicator = "IconAndTemperature"
    wind_speed_unit = "Mph"

    [settings]
    lock_cmd = "${lockCmd}"
    shutdown_cmd = "shutdown now"
    reboot_cmd = "systemctl reboot"
    suspend_cmd = "systemctl suspend"
    logout_cmd = "${logoutCmd}"
    remove_idle_btn = false
    remove_airplane_btn = ${lib.boolToString (!cfg.airplaneButton)}
    audio_sinks_more_cmd = "pavucontrol -t 3"
    audio_sources_more_cmd = "pavucontrol -t 4"
    peripheral_battery_format = "IconAndPercentage"
    peripheral_indicators = "All"
    indicators = [${tomlList cfg.indicators}]

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
    ${lib.optionalString cfg.clipboard.enable ''

      [[CustomModule]]
      name = "clipboard"
      icon = "󰅍"
      command = "cliphist list | wofi --dmenu | cliphist decode | wl-copy"
    ''}
  '';
in {
  # ANCHOR: ashell-options
  options.othrys.desktop.ashell = {
    enable = lib.mkEnableOption "Ashell status bar";

    weatherLocation = lib.mkOption {
      type = lib.types.nullOr (lib.types.either
        # A city name holds neither a brace nor an equals sign, and the raw
        # TOML table this option once took holds both, so that form is
        # refused here instead of being looked up as a city.
        (lib.types.strMatching "[^{}=]+")
        (lib.types.submodule {
          options = {
            latitude = lib.mkOption {
              type = lib.types.numbers.between (-90) 90;
              example = 40.7128;
              description = "Latitude in decimal degrees, north positive.";
            };
            longitude = lib.mkOption {
              type = lib.types.numbers.between (-180) 180;
              example = -74.006;
              description = "Longitude in decimal degrees, east positive.";
            };
          };
        }));
      default = null;
      example = lib.literalExpression ''
        {
          latitude = 40.7128;
          longitude = -74.006;
        }
      '';
      description = ''
        Where the clock's weather is for. A string is a city name, which
        ashell looks up, and an attribute set of `latitude` and `longitude`
        is a point. The module renders either as the `weather_location` value
        ashell reads. The bar fetches the forecast over the network. With
        `null` the key is left out, the bar shows no weather and makes no
        request. The location is identity-shaped, so the consuming host sets
        it.
      '';
    };

    clipboard = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Keep a clipboard history with cliphist and show the bar button that
          picks from it. The history is a plain file under `~/.cache/cliphist`
          holding everything copied, apart from entries a password manager
          marks as sensitive. It is capped at `maxItems`, wiped each time
          the session locks through `othrys.desktop.lockCommand` and wiped
          again when the graphical session ends.
        '';
      };
      maxItems = lib.mkOption {
        type = lib.types.ints.positive;
        default = 100;
        description = "Entries the clipboard history keeps before the oldest is dropped.";
      };
    };

    indicators = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [
        "IdleInhibitor"
        "PowerProfile"
        "Audio"
        "Microphone"
        "Network"
        "Vpn"
        "Bluetooth"
        "Battery"
        "PeripheralBattery"
        "Brightness"
      ]);
      default = defaultIndicators;
      defaultText = lib.literalExpression ''
        ["IdleInhibitor" "PeripheralBattery" "Audio" "Microphone"], and with
        othrys.hardware.laptop.enable also "Brightness", "Network" and
        "Battery", plus "Bluetooth" and "PowerProfile" when the host runs
        bluetooth and power-profiles-daemon
      '';
      example = ["Audio" "Network" "Battery"];
      description = ''
        The indicators in the settings group at the right of the bar, in the
        order given. The default follows the host. A desktop gets the idle
        inhibitor, audio, the microphone and peripheral batteries. A host with
        `othrys.hardware.laptop.enable` also gets its own battery, the screen
        brightness and the network, and Bluetooth and the power profile when it
        runs those services.

        `Battery` reads UPower, which the laptop module enables. `Network` reads
        NetworkManager or iwd. `PowerProfile` reads power-profiles-daemon, so
        it is left out on a host that uses TLP.
      '';
    };

    airplaneButton = lib.mkOption {
      type = lib.types.bool;
      default = laptop;
      defaultText = lib.literalExpression "config.othrys.hardware.laptop.enable";
      description = "Show the airplane mode button in the settings menu.";
    };

    clockFormat = lib.mkOption {
      type = lib.types.str;
      default =
        if laptop
        then "%a %b %d  %I:%M %p"
        else "%a %b %d  %I:%M:%S %p";
      defaultText = lib.literalExpression ''
        "%a %b %d  %I:%M:%S %p", and without the seconds when
        othrys.hardware.laptop.enable is set
      '';
      description = ''
        `strftime` format of the clock. A format with seconds makes the bar
        redraw once a second, which a laptop on battery pays for, so the
        default leaves them out there.
      '';
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

  # The assertion lives in its own mkIf because the body reads the session of
  # a compositor, so it stays unevaluated on a host that has none and the
  # assertion message is what surfaces.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = hyprlandEnabled || niriEnabled;
          message = "othrys.desktop.ashell requires a supported compositor: enable othrys.desktop.compositors.hyprland or othrys.desktop.compositors.niri.";
        }
      ];
    })
    (lib.mkIf (cfg.enable && (hyprlandEnabled || niriEnabled)) {
      # The bar's lock button runs the shared lock command, so the locker and
      # its PAM service exist here as well as in the idle module, since a
      # host can run the bar without idle management. The YubiKey module
      # adds its factor to both lockers itself.
      programs.hyprlock.enable = session.hyprlock;
      environment.systemPackages = lib.optional session.swaylock pkgs.swaylock;
      security.pam.services = lib.mkIf session.swaylock {swaylock = {};};

      # The history holds whatever was copied while the session was open, so
      # locking the session empties it. A failed wipe must not stop the lock.
      othrys.desktop.lockHooks = lib.mkIf cfg.clipboard.enable "${cliphist} wipe || true";

      # No sandbox baseline. The bar is a GPU client of the user's own
      # session, so it needs the render devices PrivateDevices hides and the
      # home directory ProtectHome hides, and its buttons start the user's
      # programs, which would inherit every restriction placed on the unit.
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
          # The locker is installed at system level above, beside its PAM
          # service. Idle management lives in othrys.desktop.idle, not here.
          ++ lib.optional hyprlandEnabled pkgs.hyprpicker;

        home.file.".config/ashell/config.toml".text = configToml;

        # The watcher that feeds the history, on either compositor. The unit
        # is Home Manager's own and starts with the graphical session.
        services.cliphist = lib.mkIf cfg.clipboard.enable {
          enable = true;
          extraOptions = ["-max-items" (toString cfg.clipboard.maxItems)];
        };

        # The history should not outlive the session that filled it either,
        # and on a host that keeps its home directory nothing else removes
        # it. The unit does nothing when it starts and wipes when it stops,
        # which is when graphical-session.target goes down at logout, reboot
        # or shutdown. It is ordered before the watcher, so it stops after
        # the watcher has and nothing is stored behind the wipe. A session
        # that ends without stopping its units, as on a power cut, leaves
        # the history for the next lock or logout.
        systemd.user.services.cliphist-wipe = lib.mkIf cfg.clipboard.enable {
          Unit = {
            Description = "Wipe the clipboard history when the session ends.";
            PartOf = ["graphical-session.target"];
            Before = ["cliphist.service"];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.coreutils}/bin/true";
            ExecStop = "${cliphist} wipe";
          };
          Install.WantedBy = ["graphical-session.target"];
        };

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
