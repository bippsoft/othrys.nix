# modules/apps/cli/ai/ollama.nix
# Local LLM inference server with GPU acceleration
{
  config,
  lib,
  ...
}: {
  options.othrys.apps.ai.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM server";

    acceleration = lib.mkOption {
      type = lib.types.enum ["cuda" "rocm" "vulkan" "cpu"];
      default =
        # Neither option is declared on nix-darwin, where the default is
        # "cpu".
        if config.othrys.hardware.nvidia.enable or false
        then "cuda"
        else if config.hardware.graphics.enable or false
        then "vulkan"
        else "cpu";
      defaultText = lib.literalMD ''
        `"cuda"` when `othrys.hardware.nvidia` is enabled, `"vulkan"` on any
        other host with `hardware.graphics.enable`, and `"cpu"` otherwise,
        which is every nix-darwin host
      '';
      description = ''
        GPU acceleration backend for Ollama, which picks the package. The
        default follows the host's GPU. Vulkan runs on AMD and Intel cards
        alike, and an AMD host that wants ROCm names it here. nix-darwin takes
        `"cpu"` alone.
      '';
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Models to pull automatically on service start. NixOS only, since Home Manager's ollama agent on nix-darwin pulls none.";
      example = ["llama3.1" "codellama"];
    };
  };
}
