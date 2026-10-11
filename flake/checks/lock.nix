# flake/checks/lock.nix
# CORE. The session lock, read back from evaluated hosts. A locker whose PAM
# service is missing rejects the correct password, and nothing but a real
# session showed it, since the package was installed and the lock command was
# right. Three hosts cover the three ways a locker is reached: the idle module
# on hyprland and on niri, and ashell's lock button with no idle module and no
# YubiKey. A compositor with neither locks before sleep and at no other time.
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
  niriAlone = host {othrys.desktop.compositors.niri.enable = true;};
  niriUnlocked = host {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.idle.lockBeforeSleep = false;
  };
  niriIdleUnlocked = host {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.idle = {
      enable = true;
      lockBeforeSleep = false;
    };
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
  runsHypridle = cfg: cfg.home-manager.users.${user}.services.hypridle.enable;
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
    "the idle module locks before sleep" = (hypridle niriIdle).general.before_sleep_cmd == "swaylock";
    "a compositor alone locks before sleep" = runsHypridle niriAlone && (hypridle niriAlone).general.before_sleep_cmd == "swaylock";
    "a compositor alone has no idle stage" = !((hypridle niriAlone) ? listener);
    "a compositor alone gets the locker and its PAM service" = niriAlone.security.pam.services ? swaylock && builtins.any (p: p.pname or "" == "swaylock") niriAlone.environment.systemPackages;
    "ashell without idle locks before sleep with the shared command" = runsHypridle hyprlandAshell && (hypridle hyprlandAshell).general.before_sleep_cmd == hyprlandAshell.othrys.desktop.lockCommand;
    "a host can turn the sleep lock off" = !runsHypridle niriUnlocked;
    "the idle module honours the sleep lock switch" = !((hypridle niriIdleUnlocked).general ? before_sleep_cmd) && (hypridle niriIdleUnlocked).general.lock_cmd == "swaylock";
    "a screen-off stage before the lock stage is rejected" = rejectedWith "timeouts must increase" unordered;
  }
