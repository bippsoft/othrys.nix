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

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address the server listens on. The default keeps it to this host.
        `"0.0.0.0"` or `"::"` serves every address, and Ollama asks for no
        credentials, so anything that reaches the port can run models. On
        NixOS the port stays closed while `networking.firewall.enable` is on,
        until the host opens it. On nix-darwin nothing closes the port, so an
        address other than loopback is reachable from the network at once.
      '';
      example = "0.0.0.0";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port the server listens on.";
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Models to pull automatically on service start. NixOS only, since Home Manager's ollama agent on nix-darwin pulls none.";
      example = ["llama3.1" "codellama"];
    };
  };
}
