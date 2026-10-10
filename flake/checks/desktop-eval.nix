# flake/checks/desktop-eval.nix
# CORE. What the desktop modules and the two terminals write, read back from
# evaluated hosts. A location service enabled for the whole host, a terminal
# that takes remote control from its own output, a scrollback of a hundred
# lines and two wallpaper daemons on one screen all evaluate cleanly, so
# each is compared here with the value the module documents.
{
  lib,
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

  user = "alice";
  home = cfg: cfg.home-manager.users.${user};
  ashellToml = cfg: (home cfg).home.file.".config/ashell/config.toml".text;

  hyprlandAshell = host {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.ashell.enable = true;
    othrys.apps.kitty.enable = true;
    othrys.apps.ghostty.enable = true;
  };
  niriAshell = host {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.ashell = {
      enable = true;
      weatherLocation = "{ Coordinates = [0.0, 0.0] }";
      clipboard.maxItems = 50;
    };
    othrys.apps.kitty = {
      enable = true;
      extraSettings.scrollback_lines = "50000";
    };
  };
  noClipboard = host {
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.ashell = {
      enable = true;
      clipboard.enable = false;
    };
  };

  # The wallpaper is only ever read as a path here, so any file serves.
  wallpaper = {othrys.system.stylix.wallpaper = ./desktop-eval.nix;};
  hyprlandNoctalia = host {
    imports = [wallpaper];
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.noctalia.enable = true;
  };
  hyprlandWallpaper = host {
    imports = [wallpaper];
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.ashell.enable = true;
  };

  both = host {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.compositors.niri.enable = true;
    othrys.desktop.idle.enable = true;
  };

  nightLight = extra:
    host {
      othrys.desktop.compositors.niri.enable = true;
      othrys.desktop.nightLight = {enable = true;} // extra;
    };
  located = nightLight {
    latitude = 0.0;
    longitude = 0.0;
  };
  geoclue = nightLight {geoclue.enable = true;};
  unlocated = nightLight {};

  floorp = host {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.compositors.niri.enable = true;
    othrys.apps.floorp.enable = true;
  };

  kitty = cfg: (home cfg).programs.kitty.settings;
  hyprlandEnv = map (e: builtins.head e._args) (home hyprlandAshell).wayland.windowManager.hyprland.settings.env;
  screenOff = cfg: (lib.last (home cfg).services.hypridle.settings.listener).on-timeout;
  userPackages = cfg: map (p: p.pname or "") (home cfg).home.packages;
  systemPackages = cfg: map (p: p.pname or "") cfg.environment.systemPackages;
in
  mkExpectations "othrys-eval-desktop" {
    "kitty takes remote control on a socket only" = (kitty hyprlandAshell).allow_remote_control == "socket-only";
    "kitty listens on a unix socket in the runtime directory" = lib.hasPrefix "unix:\${XDG_RUNTIME_DIR}/" (kitty hyprlandAshell).listen_on;
    "kitty keeps its default scrollback without extraSettings" = (kitty hyprlandAshell).scrollback_lines == "10000";
    "kitty extraSettings win over the defaults" = (kitty niriAshell).scrollback_lines == "50000";
    "kitty extraSettings leave the other defaults in place" = (kitty niriAshell).allow_remote_control == "socket-only";

    "ghostty's scrollback limit is 10 MB" = lib.toList (home hyprlandAshell).programs.ghostty.settings.scrollback-limit == [10000000];

    "geoclue is off with coordinates" = !located.services.geoclue2.enable;
    "coordinates select the manual provider" = (home located).services.gammastep.provider == "manual";
    "geoclue is on when the host asks for it" = geoclue.services.geoclue2.enable;
    "the geoclue option selects the geoclue provider" = (home geoclue).services.gammastep.provider == "geoclue2";
    "a night light with no location is rejected" = rejectedWith "needs a location" unlocated;

    "ashell writes no weather location by default" = !lib.hasInfix "weather_location" (ashellToml hyprlandAshell);
    "ashell writes the weather location a host sets" = lib.hasInfix "\nweather_location = { Coordinates = [0.0, 0.0] }\n" (ashellToml niriAshell);

    "the clipboard history runs on niri with ashell" = (home niriAshell).services.cliphist.enable;
    "the clipboard history runs on hyprland with ashell" = (home hyprlandAshell).services.cliphist.enable;
    "the clipboard history is capped" = (home niriAshell).services.cliphist.extraOptions == ["-max-items" "50"];
    "the clipboard button is in the bar" = lib.hasInfix "\"Custom:clipboard\"" (ashellToml niriAshell);
    "locking wipes the clipboard history" = lib.hasInfix "cliphist wipe" (builtins.readFile niriAshell.othrys.desktop.lockCommand);
    "the lock still ends in the locker" = lib.hasInfix "exec swaylock" (builtins.readFile niriAshell.othrys.desktop.lockCommand);
    "a host can turn the clipboard history off" = !(home noClipboard).services.cliphist.enable && !lib.hasInfix "clipboard" (ashellToml noClipboard);
    "without the history the lock command is the bare locker" = noClipboard.othrys.desktop.lockCommand == "swaylock";

    "the browser default follows floorp on hyprland" = floorp.othrys.desktop.compositors.hyprland.browser == "floorp";
    "the browser default follows floorp on niri" = floorp.othrys.desktop.compositors.niri.browser == "floorp";
    "hyprland does not export TERM" = !builtins.elem "TERM" hyprlandEnv;

    "noctalia on hyprland has a Secret Service provider" = hyprlandNoctalia.services.gnome.gnome-keyring.enable;
    "noctalia on hyprland draws the wallpaper itself" = (home hyprlandNoctalia).programs.noctalia.settings.wallpaper.enabled;
    "noctalia on hyprland starts no hyprpaper" = !(home hyprlandNoctalia).services.hyprpaper.enable;
    "hyprland without noctalia keeps hyprpaper for the Stylix wallpaper" = (home hyprlandWallpaper).services.hyprpaper.enable;

    "a host with both compositors picks the screen-off command at run time" = let
      script = builtins.readFile (screenOff both);
    in
      lib.hasInfix "XDG_CURRENT_DESKTOP" script && lib.hasInfix "hyprctl dispatch" script && lib.hasInfix "niri msg action power-off-monitors" script;
    "a host with both compositors installs both lockers" = both.programs.hyprlock.enable && builtins.elem "swaylock" (systemPackages both);
    "a host with both compositors declares both PAM services" = both.security.pam.services ? hyprlock && both.security.pam.services ? swaylock;
    "a niri host calls niri directly" =
      (screenOff (host {
        othrys.desktop.compositors.niri.enable = true;
        othrys.desktop.idle.enable = true;
      }))
      == "niri msg action power-off-monitors";

    "the file manager is a user package" = builtins.elem "nautilus" (userPackages hyprlandAshell) && !builtins.elem "nautilus" (systemPackages hyprlandAshell);
  }
