# flake/checks/desktop-eval.nix
# CORE. What the desktop modules and the two terminals write, read back from
# evaluated hosts. A location service enabled for the whole host, a terminal
# that takes remote control from its own output, a scrollback of a hundred
# lines and a graphical session with no Secret Service provider all evaluate
# cleanly, so each is compared here with the value the module documents.
{
  lib,
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  stylixModules,
}: let
  host = extra:
    hostConfig [
      functioningHost
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
      weatherLocation = {
        latitude = 12.5;
        longitude = -45.25;
      };
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
      weatherLocation = "Example City";
    };
  };
  # The raw TOML table the option took before it was typed. The type refuses
  # it, which aborts the read, so it is tried instead of asserted on.
  rawWeather =
    builtins.tryEval
    (host {
      othrys.desktop.compositors.niri.enable = true;
      othrys.desktop.ashell = {
        enable = true;
        weatherLocation = "{ Coordinates = [0.0, 0.0] }";
      };
    }).othrys.desktop.ashell.weatherLocation;

  # The wallpaper is only ever read as a path here, so any file serves.
  # hyprpaper is switched on by Stylix, so this host carries the adapter.
  wallpaper = {
    imports = [stylixModules];
    othrys.system.stylix.enable = true;
    othrys.theme.wallpaper.source = ./desktop-eval.nix;
  };
  hyprlandWallpaper = host {
    imports = [wallpaper];
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.ashell.enable = true;
  };

  # The keyring, on each compositor with the login module, turned off on
  # each, and on a host with no graphical session. niri-flake enables
  # gnome-keyring on a niri host itself, so the niri host with the option off
  # is the one that shows the option still decides.
  greeter = {othrys.desktop.login.enable = true;};
  noKeyring = {othrys.desktop.keyring.enable = false;};
  hyprlandLogin = host {
    imports = [greeter];
    othrys.desktop.compositors.hyprland.enable = true;
  };
  niriLogin = host {
    imports = [greeter];
    othrys.desktop.compositors.niri.enable = true;
  };
  hyprlandNoKeyring = host {
    imports = [greeter noKeyring];
    othrys.desktop.compositors.hyprland.enable = true;
  };
  niriNoKeyring = host {
    imports = [greeter noKeyring];
    othrys.desktop.compositors.niri.enable = true;
  };
  headless = hostConfig [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
    }
  ];
  keyring = cfg: cfg.services.gnome.gnome-keyring.enable;
  greeterUnlocks = cfg: cfg.security.pam.services.greetd.enableGnomeKeyring;

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
    "ashell renders coordinates as the table it reads" = lib.hasInfix "\nweather_location = { Coordinates = [12.5, -45.25] }\n" (ashellToml niriAshell);
    "ashell renders a city as the table it reads" = lib.hasInfix "\nweather_location = { City = \"Example City\" }\n" (ashellToml noClipboard);
    "a raw TOML weather location is refused" = !rawWeather.success;

    "the clipboard history runs on niri with ashell" = (home niriAshell).services.cliphist.enable;
    "the clipboard history runs on hyprland with ashell" = (home hyprlandAshell).services.cliphist.enable;
    "the clipboard history is capped" = (home niriAshell).services.cliphist.extraOptions == ["-max-items" "50"];
    "the clipboard button is in the bar" = lib.hasInfix "\"Custom:clipboard\"" (ashellToml niriAshell);
    "locking wipes the clipboard history" = lib.hasInfix "cliphist wipe" (builtins.readFile niriAshell.othrys.desktop.lockCommand);
    "the lock still ends in the locker" = lib.hasInfix "exec swaylock" (builtins.readFile niriAshell.othrys.desktop.lockCommand);
    "the clipboard history is wiped when the session ends" = let
      unit = (home niriAshell).systemd.user.services.cliphist-wipe;
    in
      lib.hasSuffix "cliphist wipe" unit.Service.ExecStop && unit.Unit.PartOf == ["graphical-session.target"] && unit.Unit.Before == ["cliphist.service"];
    "without the history nothing is wiped at session end" = !((home noClipboard).systemd.user.services ? cliphist-wipe);
    "a host can turn the clipboard history off" = !(home noClipboard).services.cliphist.enable && !lib.hasInfix "clipboard" (ashellToml noClipboard);
    "without the history the lock command is the bare locker" = noClipboard.othrys.desktop.lockCommand == "swaylock";

    "the browser default follows floorp on hyprland" = floorp.othrys.desktop.compositors.hyprland.browser == "floorp";
    "the browser default follows floorp on niri" = floorp.othrys.desktop.compositors.niri.browser == "floorp";
    "hyprland does not export TERM" = !builtins.elem "TERM" hyprlandEnv;

    "a hyprland host has a Secret Service provider" = hyprlandLogin.othrys.desktop.keyring.enable && keyring hyprlandLogin;
    "a niri host has a Secret Service provider" = niriLogin.othrys.desktop.keyring.enable && keyring niriLogin;
    "the greeter unlocks the keyring on hyprland" = greeterUnlocks hyprlandLogin;
    "the greeter unlocks the keyring on niri" = greeterUnlocks niriLogin;
    "a hyprland host can turn the keyring off" = !keyring hyprlandNoKeyring;
    "a niri host can turn the keyring off" = !keyring niriNoKeyring;
    "a host without the keyring leaves the greeter alone" = !greeterUnlocks hyprlandNoKeyring && !greeterUnlocks niriNoKeyring;
    "a headless host has no keyring" = !headless.othrys.desktop.keyring.enable && !keyring headless;

    "hyprland keeps hyprpaper for the Stylix wallpaper" = (home hyprlandWallpaper).services.hyprpaper.enable;

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
