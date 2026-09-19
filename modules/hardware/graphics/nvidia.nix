# modules/hardware/graphics/nvidia.nix
# NVIDIA proprietary driver and session variables
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.hardware.nvidia;
  primeEnabled = cfg.prime.enable;
in {
  options.othrys.hardware.nvidia = {
    enable = lib.mkEnableOption "NVIDIA GPU";

    openModules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use NVIDIA's open kernel modules. They support Turing and newer, which
        is GTX 16 and RTX 20 onward, and NVIDIA recommends them there.

        A Maxwell, Pascal or Volta card, which is GTX 900, GTX 10 and Titan V,
        needs `false` here together with a `package` from the 580 branch. With
        the open modules the kernel module never binds to such a card, and
        `nvidia-smi` reports that it cannot communicate with the driver.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = config.boot.kernelPackages.nvidiaPackages.stable;
      defaultText = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.stable";
      example = lib.literalExpression "config.boot.kernelPackages.nvidiaPackages.legacy_580";
      description = ''
        The driver to install, taken from the host's kernel packages so its
        kernel modules match the running kernel.

        The stable driver no longer drives every card. The 580 branch is the
        last that supports Maxwell, Pascal and Volta, and nixpkgs ships it as
        `nvidiaPackages.legacy_580`. Older cards have `legacy_470` and
        `legacy_390`. A driver that does not support the card fails the same
        way the wrong `openModules` does, with `nvidia-smi` unable to
        communicate with the driver and `NVRM` lines in `dmesg` naming the
        branch the card needs.
      '';
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
      inherit (cfg) package;
      modesetting.enable = true;
      open = cfg.openModules;
      nvidiaSettings = true;

      powerManagement.enable = lib.mkDefault primeEnabled;
      powerManagement.finegrained = lib.mkDefault false;
    };
    # GPU compute servers enable nvidia with no primary user, so this is the
    # only nvidia setting that needs one.

    othrys.internal.homeConfig."hardware.nvidia".home.sessionVariables =
      if primeEnabled
      then {
        LIBVA_DRIVER_NAME = "iHD";
        VDPAU_DRIVER = "va_gl";
      }
      else {
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
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
