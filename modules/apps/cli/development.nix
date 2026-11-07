# modules/apps/cli/development.nix
# Development tools (Nix tooling, direnv)
#
# Git configuration lives in othrys.system.git, not here.
{lib, ...}: {
  options.othrys.apps.development = {
    enable = lib.mkEnableOption "Development tools";
  };
}
