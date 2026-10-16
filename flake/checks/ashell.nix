# flake/checks/ashell.nix
# EXTENDED. The ashell bar's generated config.toml, read back for a desktop, for
# a laptop, and for a host that sets its own indicator list. The fixtures carry
# a compositor, since the bar reads its session, which puts this beside the
# desktop evaluations and not in the core tier.
{
  lib,
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.desktop.compositors.niri.enable = true;
        othrys.desktop.ashell.enable = true;
      }
      extra
    ];

  tomlOf = cfg: cfg.home-manager.users.${cfg.othrys.system.user.name}.home.file.".config/ashell/config.toml".text;
  has = line: cfg: lib.hasInfix "\n${line}\n" (tomlOf cfg);

  desktop = host {};
  laptop = host {
    othrys.hardware.laptop.enable = true;
    hardware.bluetooth.enable = true;
  };
  ppdLaptop = host {
    othrys.hardware.laptop = {
      enable = true;
      tlp.enable = false;
    };
    services.power-profiles-daemon.enable = true;
  };
  custom = host {
    othrys.hardware.laptop.enable = true;
    othrys.desktop.ashell = {
      indicators = ["Audio" "Battery"];
      clockFormat = "%H:%M";
      airplaneButton = false;
    };
  };
  metric = host {
    othrys.desktop.ashell = {
      region = "de_DE";
      systemTemperatureUnit = null;
    };
  };
  localeUnits = host {othrys.desktop.ashell.region = null;};

  # Every picker moved off wofi, the run prompt and the history dropped.
  ownPickers = host {
    othrys.desktop = {
      launcherCommand = ["fuzzel"];
      emojiCommand = ["fuzzel" "--emoji"];
      runCommand = null;
      fileSearchCommand = ["fsearch"];
      ashell.clipboard.enable = false;
    };
  };
  # A dmenu other than wofi, with the history kept.
  ownMenu = host {
    othrys.desktop = {
      launcherCommand = ["fuzzel"];
      emojiCommand = null;
      runCommand = null;
      dmenuCommand = ["fuzzel" "--dmenu"];
    };
  };
  # An NVIDIA desktop with the animations on.
  nvidia = host {
    othrys.hardware.nvidia.enable = true;
    othrys.desktop.ashell.animations = true;
  };
  hyprland = hostConfig [
    functioningHost
    {
      othrys.desktop.compositors.hyprland.enable = true;
      othrys.desktop.ashell.enable = true;
      othrys.desktop.fileSearchCommand = ["fsearch"];
    }
  ];

  home = cfg: cfg.home-manager.users.${cfg.othrys.system.user.name};
  binds = cfg: (home cfg).programs.niri.settings.binds;
  spawnOf = chord: cfg: (binds cfg).${chord}.action.spawn or null;
  installs = name: cfg: builtins.any (p: (p.pname or "") == name) (home cfg).home.packages;
  unitEnv = cfg: cfg.systemd.user.services.ashell.serviceConfig.Environment;
  hyprlandLua = cfg: (home cfg).xdg.configFile."hypr/hyprland.lua".text;
in
  mkExpectations "othrys-eval-ashell" {
    "a desktop keeps the indicators it always had" = has ''indicators = ["IdleInhibitor", "PeripheralBattery", "Audio", "Microphone"]'' desktop;
    "a desktop keeps the clock with seconds" = has ''clock_format = "%a %b %d  %I:%M:%S %p"'' desktop;
    "a desktop hides the airplane button" = has "remove_airplane_btn = true" desktop;
    "a laptop gets its battery, brightness, network and bluetooth" = has ''indicators = ["IdleInhibitor", "Audio", "Microphone", "Brightness", "Network", "Bluetooth", "PeripheralBattery", "Battery"]'' laptop;
    "a laptop's clock drops the seconds" = has ''clock_format = "%a %b %d  %I:%M %p"'' laptop;
    "a laptop shows the airplane button" = has "remove_airplane_btn = false" laptop;
    "the laptop module turns UPower on for the battery indicator" = laptop.services.upower.enable;
    "a desktop does not get UPower from the laptop module" = !desktop.services.upower.enable;
    "PowerProfile appears only with power-profiles-daemon" = has ''indicators = ["IdleInhibitor", "PowerProfile", "Audio", "Microphone", "Brightness", "Network", "PeripheralBattery", "Battery"]'' ppdLaptop;
    "a host's own indicator list wins" = has ''indicators = ["Audio", "Battery"]'' custom;
    "a host's own clock format wins" = has ''clock_format = "%H:%M"'' custom;
    "the weather is imperial by default" = has ''region = "en_US"'' desktop;
    "the sensor temperature is in Celsius by default" = has ''units = "Celsius"'' desktop;
    "no threshold or wind unit is written, so both follow their unit" = !lib.hasInfix "warn_threshold = 140" (tomlOf desktop) && !lib.hasInfix "wind_speed_unit" (tomlOf desktop);
    "a host's own region wins, and the sensor can follow it" = has ''region = "de_DE"'' metric && !lib.hasInfix "units = " (tomlOf metric);
    "without a region the key is left out" = !lib.hasInfix "region = " (tomlOf localeUnits);
    "a host can hide the airplane button on a laptop" = has "remove_airplane_btn = true" custom;
    "the bar opacity is written to the opacity table" = has "[appearance.opacity]\nbar = 1.000000" desktop;
    "no key is written where ashell does not read it" =
      !lib.hasInfix "max_title_length" (tomlOf desktop) && !lib.hasInfix "\nopacity = " (tomlOf desktop);
    "the animations are off by default" = has "[animations]\nenabled = false" desktop;
    "a host can turn the animations on" = has "[animations]\nenabled = true" nvidia;
    "the bar draws with Vulkan by default" = unitEnv desktop == "WGPU_BACKEND=vulkan";
    "an NVIDIA host draws the bar with OpenGL" = unitEnv nvidia == "WGPU_BACKEND=gl";

    "the emoji chord runs rofimoji by default" = builtins.head (spawnOf "Mod+E" desktop) == "rofimoji";
    "the run chord runs wofi by default" = spawnOf "Mod+Shift+D" desktop == ["wofi" "--show" "run"];
    "the clipboard chord pipes cliphist through wofi" = let
      argv = spawnOf "Mod+Shift+V" desktop;
    in
      lib.take 2 argv == ["sh" "-c"] && lib.hasInfix " list | wofi --dmenu | " (lib.last argv);
    "the clipboard button runs the same pipeline" = lib.hasInfix " list | wofi --dmenu | " (tomlOf desktop);
    "no file search chord is bound by default" = spawnOf "Mod+Shift+F" desktop == null;
    "wofi, rofimoji and wtype are installed by default" = installs "wofi" desktop && installs "rofimoji" desktop && installs "wtype" desktop;

    "a host's own pickers are bound" =
      spawnOf "Mod+E" ownPickers == ["fuzzel" "--emoji"] && spawnOf "Mod+Shift+F" ownPickers == ["fsearch"];
    "a null run command leaves its chord unbound" = spawnOf "Mod+Shift+D" ownPickers == null;
    "no history leaves the clipboard chord and button out" =
      spawnOf "Mod+Shift+V" ownPickers == null && !lib.hasInfix "name = \"clipboard\"" (tomlOf ownPickers);
    "a host that names no wofi tool installs none" =
      !(installs "wofi" ownPickers || installs "rofimoji" ownPickers || installs "wtype" ownPickers);
    "the history follows the host's own menu" = lib.hasInfix " list | fuzzel --dmenu | " (lib.last (spawnOf "Mod+Shift+V" ownMenu));
    "a null emoji command leaves its chord unbound" = spawnOf "Mod+E" ownMenu == null;
    "Hyprland binds the clipboard and file search chords" =
      lib.hasInfix "SHIFT + V" (hyprlandLua hyprland) && lib.hasInfix "exec_cmd(\"fsearch\")" (hyprlandLua hyprland);
  }
