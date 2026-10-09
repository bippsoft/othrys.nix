# flake/checks/lock.nix
# CORE. The session lock, read back from evaluated hosts. A locker whose PAM
# service is missing rejects the correct password, and nothing but a real
# session showed it, since the package was installed and the lock command was
# right. Four hosts cover the four ways a locker is reached: the idle module
# on hyprland and on niri, ashell's lock button with no idle module and no
# YubiKey, and noctalia, whose IPC lock falls back to the compositor's locker.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
}: let
  host = extra:
    hostConfig [
      functioningHost
      {othrys.system.stylix.enable = true;}
      extra
    ];

  hyprlandIdle = host {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.idle.enable = true;
  };
  niriIdle = host {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.idle.enable = true;
    othrys.desktop.idle.timeouts = {
      dim = 240;
      lock = 300;
      screenOff = 330;
      suspend = 1800;
    };
  };
  hyprlandAshell = host {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.ashell.enable = true;
  };
  niriNoctalia = host {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.noctalia.enable = true;
    othrys.desktop.idle.timeouts.suspend = 1800;
  };
  unordered = host {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.idle.enable = true;
    othrys.desktop.idle.timeouts = {
      lock = 400;
      screenOff = 300;
    };
  };

  user = hyprlandIdle.othrys.system.user.name;
  hypridle = cfg: cfg.home-manager.users.${user}.services.hypridle.settings;
  noctalia = niriNoctalia.home-manager.users.${user}.programs.noctalia.settings;
  lockScript = builtins.readFile niriNoctalia.othrys.desktop.lockCommand;
  hasInfix = needle: s: builtins.match ".*${needle}.*" s != null;
  timeouts = cfg: map (l: l.timeout) (hypridle cfg).listener;
in
  mkExpectations "othrys-eval-lock" {
    "hyprland with idle declares the hyprlock PAM service" = hyprlandIdle.security.pam.services ? hyprlock;
    "hyprland with idle locks with hyprlock" = hyprlandIdle.othrys.desktop.lockCommand == "hyprlock";
    "niri with idle declares the swaylock PAM service" = niriIdle.security.pam.services ? swaylock;
    "niri with idle locks with swaylock" = niriIdle.othrys.desktop.lockCommand == "swaylock";
    "niri with idle installs swaylock" = builtins.any (p: p.pname or "" == "swaylock") niriIdle.environment.systemPackages;
    "the idle stages are rendered in order" = timeouts niriIdle == [240 300 330 1800];
    "ashell without idle or a YubiKey declares the hyprlock PAM service" = hyprlandAshell.security.pam.services ? hyprlock;
    "ashell without a YubiKey adds no touch factor" = !hyprlandAshell.security.pam.services.hyprlock.u2f.enable;
    "noctalia locks through its IPC first" = hasInfix "noctalia msg session lock" lockScript;
    "noctalia falls back to swaylock on niri" = hasInfix "bin/swaylock" lockScript;
    "noctalia declares the fallback locker's PAM service" = niriNoctalia.security.pam.services ? swaylock;
    "noctalia locks after the idle lock timeout" =
      noctalia.idle.behavior.lock
      == {
        action = "lock";
        enabled = true;
        timeout = 300;
      };
    "noctalia turns the screen off after the idle screenOff timeout" = noctalia.idle.behavior."screen-off".timeout == 330;
    "noctalia suspends after the idle suspend timeout" = noctalia.idle.behavior.suspend.enabled && noctalia.idle.behavior.suspend.timeout == 1800;
    "a null idle stage is rendered disabled for noctalia" =
      !(host {
        othrys.desktop.compositors.niri.enable = true;
        othrys.desktop.noctalia.enable = true;
      }).home-manager.users.${
        user
      }.programs.noctalia.settings.idle.behavior.suspend.enabled;
    "a screen-off stage before the lock stage is rejected" = rejectedWith "timeouts must increase" unordered;
  }
