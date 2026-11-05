# modules/apps/cli/ai/llm-agents.nix
# Helpers for the AI modules whose package defaults to the llm-agents input
{
  lib,
  pkgs,
  othrysInputs,
}: {
  # The package of that name from the llm-agents flake this library locks.
  package = name: othrysInputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.${name};

  # llm-agents relabels its unfree licence as free, so nixpkgs never asks
  # whether the host admits unfree software. This asks the host's own
  # nixpkgs instead, by each route nixpkgs admits an unfree package, which
  # is what othrys.system.nix.allowUnfree and an external pkgs both feed.
  unfreeAllowed = name:
    (pkgs.config.allowUnfree or false)
    || builtins.elem name (pkgs.config.allowUnfreePackages or [])
    || builtins.elem lib.licenses.unfree (pkgs.config.allowlistedLicenses or [])
    || (pkgs.config.allowUnfreePredicate or (_: false)) {
      pname = name;
      inherit name;
      meta.license = lib.licenses.unfree;
    };

  unfreeMessage = option: name: "${option}: ${name} is unfree, and the llm-agents input marks it free so nixpkgs never checks. Set othrys.system.nix.allowUnfree, or admit ${name} in the host's own allowUnfreePredicate or allowUnfreePackages.";
}
