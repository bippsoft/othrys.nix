# modules/apps/cli/ai/ollama.nix
# Local LLM inference server with GPU acceleration
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.ollama;

  packageMap = {
    cuda = pkgs.ollama-cuda;
    rocm = pkgs.ollama-rocm;
    vulkan = pkgs.ollama-vulkan;
    cpu = pkgs.ollama-cpu;
  };
in {
  options.othrys.apps.ai.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM server";

    acceleration = lib.mkOption {
      type = lib.types.enum ["cuda" "rocm" "vulkan" "cpu"];
      default =
        if config.othrys.hardware.nvidia.enable
        then "cuda"
        else if config.hardware.graphics.enable
        then "vulkan"
        else "cpu";
      defaultText = lib.literalMD ''
        `"cuda"` when `othrys.hardware.nvidia` is enabled, `"vulkan"` on any
        other host with `hardware.graphics.enable`, and `"cpu"` otherwise
      '';
      description = ''
        GPU acceleration backend for Ollama, which picks the package. The
        default follows the host's GPU. Vulkan runs on AMD and Intel cards
        alike, and an AMD host that wants ROCm names it here.
      '';
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Models to pull automatically on service start.";
      example = ["llama3.1" "codellama"];
    };
  };

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = packageMap.${cfg.acceleration};
      inherit (cfg) loadModels;
    };

    othrys.internal.persist."apps.ai.ollama" = {
      directories = [
        {
          directory = "/var/lib/private/ollama";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.ai.ollama" = {
      home.sessionVariables = {
        OLLAMA_HOST = "http://127.0.0.1:11434";
      };
    };
  };
}
