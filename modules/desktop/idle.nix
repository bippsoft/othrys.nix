# modules/desktop/idle.nix
# Staged idle policy, lock then screen off then optional suspend, via hypridle
# (ext-idle-notify, which works on hyprland and niri alike). The lock command
# comes from the othrys.desktop.lockCommand signal, while the screen-off dispatch
# is compositor-flavored. Noctalia hosts are excluded, since the shell owns idle
# behavior there.
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.desktop.idle;
  hyprlandEnabled = config.othrys.desktop.compositors.hyprland.enable;

  # Under Hyprland's Lua config provider `hyprctl dispatch` is a shorthand for
  # hl.dispatch(...), so the argument is a Lua expression rather than a
  # hyprlang dispatcher name.
  screenOff =
    if hyprlandEnabled
    then "hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'"
    else "niri msg action power-off-monitors";
  screenOn =
    if hyprlandEnabled
    then "hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'"
    else "niri msg action power-on-monitors";

  mkListener = timeout: onTimeout: onResume:
    lib.optional (timeout != null) ({
        inherit timeout;
        on-timeout = onTimeout;
      }
      // lib.optionalAttrs (onResume != null) {on-resume = onResume;});
in {
  # ANCHOR: idle-options
  options.othrys.desktop.idle = {
    enable = lib.mkEnableOption "staged idle management (dim, lock, screen off, suspend) via hypridle";

    lockCommand = lib.mkOption {
      type = lib.types.str;
      default = config.othrys.desktop.lockCommand;
      defaultText = lib.literalExpression "config.othrys.desktop.lockCommand";
      description = "Command the lock stage runs (and before-sleep lock).";
    };

    timeouts = {
      dim = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 240;
        description = "Seconds of idle before dimming the backlight (brightnessctl); null disables the stage.";
      };
      lock = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = 300;
        description = "Seconds of idle before locking; null disables the stage.";
      };
      screenOff = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = 330;
        description = "Seconds of idle before turning displays off; null disables the stage.";
      };
      suspend = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 1800;
        description = "Seconds of idle before suspending; null disables the stage (desktops usually want null, laptops a value).";
      };
    };
  };
  # ANCHOR_END: idle-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.othrys.desktop.graphical;
        message = "othrys.desktop.idle requires a graphical session: enable a compositor module (or set othrys.desktop.graphical for an unmanaged one).";
      }
      {
        assertion = !config.othrys.desktop.noctalia.enable;
        message = "othrys.desktop.idle conflicts with othrys.desktop.noctalia, which manages idle and locking itself.";
      }
    ];

    home-manager.users.${username} = {
      # The lock stage needs its locker on PATH even on bar-less hosts
      # (deduplicated with ashell's copy when both are enabled).
      home.packages =
        [
          (
            if hyprlandEnabled
            then pkgs.hyprlock
            else pkgs.swaylock
          )
        ]
        ++ lib.optional (cfg.timeouts.dim != null) pkgs.brightnessctl;

      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = cfg.lockCommand;
            before_sleep_cmd = cfg.lockCommand;
            after_sleep_cmd = screenOn;
          };

          listener =
            mkListener cfg.timeouts.dim "brightnessctl --save set 10%" "brightnessctl --restore"
            ++ mkListener cfg.timeouts.lock cfg.lockCommand null
            ++ mkListener cfg.timeouts.screenOff screenOff screenOn
            ++ mkListener cfg.timeouts.suspend "systemctl suspend" null;
        };
      };
    };
  };
}
