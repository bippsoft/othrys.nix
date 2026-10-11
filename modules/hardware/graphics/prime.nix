# modules/hardware/graphics/prime.nix
# PRIME offload configuration for hybrid GPU setups (Intel + NVIDIA)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.hardware.nvidia.prime;
  nvidiaEnabled = config.othrys.hardware.nvidia.enable;
  busIdsSet = cfg.intelBusId != null && cfg.nvidiaBusId != null;
in {
  # ANCHOR: prime-options
  options.othrys.hardware.nvidia.prime = {
    enable = lib.mkEnableOption "PRIME offload (hybrid GPU)";

    intelBusId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      defaultText = lib.literalMD "none, and PRIME refuses to evaluate until it is set";
      example = "PCI:0:2:0";
      description = ''
        PCI bus ID of the Intel iGPU. `lspci | grep VGA` prints the address
        in hexadecimal as `00:02.0`, and the option takes it in decimal as
        `PCI:0:2:0`. The address differs between boards, and a wrong one
        boots to a black screen, which is why there is no default.
      '';
    };

    nvidiaBusId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      defaultText = lib.literalMD "none, and PRIME refuses to evaluate until it is set";
      example = "PCI:1:0:0";
      description = "PCI bus ID of the NVIDIA GPU, read from `lspci | grep NVIDIA` and written the same way as `intelBusId`.";
    };

    finegrainedPowerManagement = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable fine-grained power management (experimental).";
    };
  };
  # ANCHOR_END: prime-options

  config = lib.mkMerge [
    # The assertions sit outside the nvidia guard. Inside it, PRIME on a host
    # without the driver would configure nothing and say nothing.
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = nvidiaEnabled;
          message = "othrys.hardware.nvidia.prime: PRIME offload needs the NVIDIA driver, so set othrys.hardware.nvidia.enable = true.";
        }
        {
          assertion = busIdsSet;
          message = "othrys.hardware.nvidia.prime: set intelBusId and nvidiaBusId to the addresses `lspci` reports, written as PCI:<bus>:<device>:<function> in decimal.";
        }
      ];
    })

    # The body waits for the bus ids as well, since a null would reach the
    # NixOS options as a type error before the assertion above could report.
    (lib.mkIf (nvidiaEnabled && cfg.enable && busIdsSet) {
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

      # No kernel parameter is set here. nixpkgs writes nvidia-drm.modeset=1
      # into the modprobe configuration whenever offload is on, and
      # nvidia.NVreg_PreserveVideoMemoryAllocations=1 whenever
      # hardware.nvidia.powerManagement.enable is, which nvidia.nix turns on
      # for a PRIME host. The second one needs the suspend services that
      # option installs, so it follows the option and a host that turns power
      # management off loses both together. i915 has had no enable_rc6
      # parameter since Linux 4.16 and RC6 is on wherever the hardware has it.

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
    })
  ];
}
