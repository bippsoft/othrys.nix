# modules/apps/cli/ai/ollama.darwin.nix
# The nix-darwin implementation of othrys.apps.ai.ollama
#
# nix-darwin has no ollama service, so the server is Home Manager's
# services.ollama, which runs it as the user's launchd agent and reaches the
# user through darwinModules.home on the address othrys.apps.ai.ollama.host
# and .port name. The cuda, rocm and vulkan variants are Linux only, so
# "cpu" names nixpkgs' one darwin build, and Home Manager's module pulls no
# models.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.ollama;
  address = import ../../../lib/ollama.nix {inherit lib;};
  net = import ../../../lib/net.nix {inherit lib;};
in {
  imports = [./ollama.nix];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acceleration == "cpu";
        message = "othrys.apps.ai.ollama.acceleration is \"${cfg.acceleration}\", and nixpkgs builds that package for Linux alone. Set it to \"cpu\" on a darwin host.";
      }
      {
        assertion = cfg.loadModels == [];
        message = "othrys.apps.ai.ollama.loadModels is set on a darwin host, and Home Manager's ollama agent pulls no models. Leave it empty and run `ollama pull` by hand.";
      }
    ];

    # A function, so the client reads the agent's merged values from the
    # user's own configuration, and a host that sets Home Manager's options
    # itself still points the client at the agent.
    othrys.internal.homeConfig."apps.ai.ollama" = {config, ...}: {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cpu;
        host = lib.mkDefault (address.serverHost cfg.host);
        port = lib.mkDefault cfg.port;
      };
      home.sessionVariables.OLLAMA_HOST = "http://${net.local config.services.ollama.host}:${toString config.services.ollama.port}";
    };
  };
}
