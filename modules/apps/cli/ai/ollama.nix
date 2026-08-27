# modules/apps/cli/ai/ollama.nix
# Local LLM inference server with GPU acceleration
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.ai.ollama;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

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
      default = "cuda";
      description = "GPU acceleration backend for Ollama.";
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

    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/private/ollama";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    home-manager.users.${username} = {
      home.sessionVariables = {
        OLLAMA_HOST = "http://127.0.0.1:11434";
      };
    };
  };
}
