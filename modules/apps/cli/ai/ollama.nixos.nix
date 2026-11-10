# modules/apps/cli/ai/ollama.nixos.nix
# The NixOS implementation of othrys.apps.ai.ollama
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.ollama;
  address = import ../../../lib/ollama.nix {inherit lib;};
  net = import ../../../lib/net.nix {inherit lib;};
  server = config.services.ollama;

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
      host = lib.mkDefault (address.serverHost cfg.host);
      port = lib.mkDefault cfg.port;
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
        # Read from the server's merged values, so a host that sets the
        # upstream options itself still points the client at the server.
        OLLAMA_HOST = "http://${net.local server.host}:${toString server.port}";
      };
    };
  };
}
