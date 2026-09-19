# flake/checks/ashell.nix
# EXTENDED. The ashell bar's generated config.toml, read back for a desktop, for
# a laptop, and for a host that sets its own indicator list. The fixtures carry
# Stylix and a compositor, since the bar interpolates both, which puts this
# beside the desktop evaluations and not in the core tier.
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
        othrys.system.stylix.enable = true;
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
    "a host can hide the airplane button on a laptop" = has "remove_airplane_btn = true" custom;
  }
