# modules/hardware/graphics/prime.nix
# PRIME offload configuration for hybrid GPU setups (Intel + NVIDIA)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.hardware.nvidia.prime;
in {
  # ANCHOR: prime-options
  options.othrys.hardware.nvidia.prime = {
    enable = lib.mkEnableOption "PRIME offload (hybrid GPU)";

    intelBusId = lib.mkOption {
      type = lib.types.str;
      default = "PCI:0:2:0";
      description = "PCI bus ID for Intel iGPU (from lspci | grep VGA).";
    };

    nvidiaBusId = lib.mkOption {
      type = lib.types.str;
      default = "PCI:1:0:0";
      description = "PCI bus ID for NVIDIA GPU (from lspci | grep NVIDIA).";
    };

    finegrainedPowerManagement = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable fine-grained power management (experimental).";
    };
  };
  # ANCHOR_END: prime-options

  config = lib.mkIf (config.othrys.hardware.nvidia.enable && cfg.enable) {
    hardware.nvidia = {
      powerManagement.finegrained = cfg.finegrainedPowerManagement;

      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };

        inherit (cfg) intelBusId nvidiaBusId;
      };
    };

    # Kernel parameters for hybrid
    boot.kernelParams = [
      "nvidia-drm.modeset=1"
      "nvidia.NVreg_PreserveVideoMemoryAllocations=1"
      "i915.enable_rc6=1"
    ];

    # GPU monitoring and offload tools
    # powertop lives in the laptop module, and nvidia-offload is already provided by
    # prime.offload.enableOffloadCmd, and nvidia-run is the same with a message.
    environment.systemPackages = with pkgs; [
      nvtopPackages.full
      intel-gpu-tools
      vulkan-tools
      mesa-demos

      (writeShellScriptBin "nvidia-run" ''
        echo "Running on NVIDIA GPU..."
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
        export __GLX_VENDOR_LIBRARY_NAME=nvidia
        export __VK_LAYER_NV_optimus=NVIDIA_only
        exec "$@"
      '')
    ];
  };
}
