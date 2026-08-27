# modules/hardware/graphics/nvidia.nix
# NVIDIA proprietary driver and session variables
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.hardware.nvidia;
  primeEnabled = cfg.prime.enable;
in {
  options.othrys.hardware.nvidia = {
    enable = lib.mkEnableOption "NVIDIA GPU";

    openModules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use open-source kernel modules (RTX 20+ series).";
    };
  };

  # ANCHOR: nvidia-config
  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      enable32Bit = true;

      extraPackages = with pkgs;
        [
          libva-vdpau-driver
          libvdpau-va-gl
          nvidia-vaapi-driver
        ]
        ++ lib.optionals primeEnabled [
          intel-media-driver
        ];

      extraPackages32 = with pkgs.pkgsi686Linux; [
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    services.xserver.videoDrivers =
      if primeEnabled
      then ["modesetting" "nvidia"]
      else ["nvidia"];

    hardware.nvidia = {
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      modesetting.enable = true;
      open = cfg.openModules;
      nvidiaSettings = true;

      powerManagement.enable = lib.mkDefault primeEnabled;
      powerManagement.finegrained = lib.mkDefault false;
    };

    # Per-user session variables only when othrys manages the user account.
    # GPU compute servers enable nvidia without one (see modules/system/nix.nix).
    home-manager.users = lib.mkIf hmEnabled {
      ${username}.home.sessionVariables =
        if primeEnabled
        then {
          LIBVA_DRIVER_NAME = "iHD";
          VDPAU_DRIVER = "va_gl";
        }
        else {
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        };
    };

    boot.initrd.kernelModules =
      [
        "nvidia"
        "nvidia_modeset"
        "nvidia_uvm"
        "nvidia_drm"
      ]
      ++ lib.optionals primeEnabled [
        "i915"
      ];

    boot.blacklistedKernelModules =
      ["nouveau"]
      ++ lib.optionals (!primeEnabled) [
        "i915"
      ];
  };
  # ANCHOR_END: nvidia-config
}
