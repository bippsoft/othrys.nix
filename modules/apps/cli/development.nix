# modules/apps/cli/development.nix
# Development tools (Nix tooling, direnv)
# Git configuration lives in othrys.system.git, not here.
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.development;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
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

    # The allow database, so a `direnv allow` outlives the root wipe. It lives
    # here rather than in the zsh module because this module is what turns
    # direnv on, and a host can run it without zsh.
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        ".local/share/direnv"
      ];
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
