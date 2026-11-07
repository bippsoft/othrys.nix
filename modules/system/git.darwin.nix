# modules/system/git.darwin.nix
# The nix-darwin implementation of othrys.system.git
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./git.nix];

  # nix-darwin has no programs.git, and the git macOS ships at /usr/bin is
  # a stub that asks for the Command Line Tools, so the package is installed
  # for every user as programs.git.enable does on NixOS.
  config = lib.mkIf config.othrys.system.git.enable {
    environment.systemPackages = [pkgs.git];
  };
}
