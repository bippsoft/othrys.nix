# modules/apps/cli/development.nix
# Development tools (Nix tooling, direnv)
# Git configuration lives in othrys.system.git, not here.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.development;
in {
  options.othrys.apps.development = {
    enable = lib.mkEnableOption "Development tools";
  };

  config = lib.mkIf cfg.enable {
    # direnv is enabled system-wide so it hooks every shell (including root)
    # and non-interactive `nix develop` invocations.
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Placement rule. System Nix tooling lives in environment.systemPackages, NOT
    # home-manager, because these operate on the system itself and are needed
    # in root/sudo contexts (`sudo nixos-rebuild ... |& nom`, `nh os switch`,
    # CI/pre-commit running as any user). User-facing apps go to home-manager.
    # See the Package Placement section of CONTRIBUTING.md.
    # (nh itself is installed by programs.nh, see modules/system/nix.nix.)
    environment.systemPackages = with pkgs; [
      # Nix tooling
      alejandra
      deadnix
      statix
      manix
      nix-output-monitor
      nvd
      nix-tree
    ];
  };
}
