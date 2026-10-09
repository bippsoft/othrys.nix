# modules/desktop/idle.nix
# Staged idle policy, lock then screen off then optional suspend, via hypridle
# (ext-idle-notify, which works on hyprland and niri alike). The lock command
# comes from the othrys.desktop.lockCommand signal, while the screen-off dispatch
# is compositor-flavored. Noctalia hosts are excluded, since the shell owns idle
# behavior there, and noctalia.nix reads the timeouts declared here for its
# own idle behaviors, so one set of numbers describes every host.
{
  config,
  lib,
  pkgs,
  ...
}: let
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

    # Read by noctalia.nix as well, which runs its own idle manager, so the
    # stages below describe a noctalia host too even though idle.enable is off
    # there.
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
      {
        # A later stage that fires before an earlier one makes the earlier
        # one pointless, and a screen that is off before it is locked is an
        # unlocked session nobody is looking at.
        assertion = let
          stages = builtins.filter (t: t != null) [cfg.timeouts.dim cfg.timeouts.lock cfg.timeouts.screenOff cfg.timeouts.suspend];
          ordered = l: builtins.length l < 2 || (builtins.head l < builtins.elemAt l 1 && ordered (builtins.tail l));
        in
          ordered stages;
        message = "othrys.desktop.idle.timeouts must increase from dim to lock to screenOff to suspend; a stage set to null is skipped.";
      }
    ];

    # The locker is a PAM client, and a PAM service that is not declared
    # denies every attempt, so a lock screen with no service cannot be
    # unlocked. programs.hyprlock declares hyprlock's and installs the
    # package. swaylock has no NixOS module, and niri-flake declares its
    # service only on niri hosts, so it is declared here for every host that
    # locks with it.
    programs.hyprlock.enable = hyprlandEnabled;
    security.pam.services = lib.mkIf (!hyprlandEnabled) {swaylock = {};};
    environment.systemPackages = lib.optional (!hyprlandEnabled) pkgs.swaylock;

    othrys.internal.homeConfig."desktop.idle" = {
      home.packages = lib.optional (cfg.timeouts.dim != null) pkgs.brightnessctl;

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
