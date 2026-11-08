# modules/apps/cli/ai/ollama.darwin.nix
# The nix-darwin implementation of othrys.apps.ai.ollama
#
# nix-darwin has no ollama service, so the server is Home Manager's
# services.ollama, which runs it as the user's launchd agent and reaches the
# user through darwinModules.home on Home Manager's default address,
# 127.0.0.1:11434. The cuda, rocm and vulkan variants are Linux only, so
# "cpu" names nixpkgs' one darwin build, and Home Manager's module pulls no
# models.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.ollama;
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

    othrys.internal.homeConfig."apps.ai.ollama" = {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-cpu;
      };
      home.sessionVariables.OLLAMA_HOST = "http://127.0.0.1:11434";
    };
  };
}
