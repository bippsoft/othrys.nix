# flake/checks/login.nix
# CORE. What the login module hands greetd, read back from evaluated hosts.
# The default session has to exist on the host that starts it, the greeter
# has to run as its own account, and autologin has to come with a lock path,
# since none of that fails evaluation on its own.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
}: let
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.system.stylix.enable = true;
        othrys.desktop.login.enable = true;
      }
      extra
    ];

  hyprland = host {othrys.desktop.compositors.hyprland.enable = true;};
  niri = host {othrys.desktop.compositors.niri.enable = true;};
  unmanaged = host {othrys.desktop.graphical = true;};
  autoLoginNoLock = host {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.login.autoLogin = true;
  };
  autoLogin = host {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.idle.enable = true;
    othrys.desktop.login.autoLogin = true;
  };

  greetd = cfg: cfg.services.greetd.settings;
  hasInfix = needle: s: builtins.match ".*${needle}.*" s != null;
in
  mkExpectations "othrys-eval-login" {
    "a hyprland host starts its uwsm session" = hyprland.othrys.desktop.login.sessionCommand == "uwsm start hyprland-uwsm.desktop";
    "a hyprland host registers that session with uwsm" = hyprland.programs.uwsm.waylandCompositors ? hyprland;
    "a hyprland host registers the session without othrys.desktop.uwsm" = !hyprland.othrys.desktop.uwsm.enable;
    "a niri host starts niri-session" = niri.othrys.desktop.login.sessionCommand == "niri-session";
    "the greeter runs as the greeter account" = (greetd hyprland).default_session.user == "greeter";
    "the greeter command carries the session" = hasInfix "uwsm start hyprland-uwsm.desktop" (greetd hyprland).default_session.command;
    "tuigreet is declared a text greeter" = hyprland.services.greetd.useTextGreeter;
    "no autologin session is rendered by default" = !((greetd hyprland) ? initial_session);
    "autologin starts the session as the primary user" = (greetd autoLogin).initial_session.user == autoLogin.othrys.system.user.name;
    "a host with no compositor and no command is rejected" = rejectedWith "no session to start" unmanaged;
    "autologin without a lock path is rejected" = rejectedWith "needs a lock path" autoLoginNoLock;
  }
