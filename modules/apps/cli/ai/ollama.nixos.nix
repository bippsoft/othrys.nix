# modules/apps/cli/ai/ollama.nixos.nix
# The NixOS implementation of othrys.apps.ai.ollama
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
  imports = [./ollama.nix];

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
