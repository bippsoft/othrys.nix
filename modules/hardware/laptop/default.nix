# modules/hardware/laptop/default.nix
# Common laptop features, covering power management, touchpad and brightness
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.hardware.laptop;
in {
  imports = [
    ./powerspec-1710.nix
  ];

  options.othrys.hardware.laptop = {
    enable = lib.mkEnableOption "Laptop-specific features";

    tlp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TLP power management.";
      };
    };

    touchpad = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable touchpad support.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Power management with TLP
    services.tlp = lib.mkIf cfg.tlp.enable {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      };
    };

    # Touchpad support
    services.libinput.enable = cfg.touchpad.enable;

    # Laptop-specific packages
    environment.systemPackages = with pkgs; [
      brightnessctl
      acpi
    ];

    # User packages, only when othrys manages the user account (headless
    # laptop servers exist, see modules/system/nix.nix for the guard rationale).
    home-manager.users = lib.mkIf hmEnabled {
      ${username}.home.packages = with pkgs; [
        powertop
      ];
    };
  };
}
