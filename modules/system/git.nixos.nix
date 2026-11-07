# modules/system/git.nixos.nix
# The NixOS implementation of othrys.system.git
{
  config,
  lib,
  ...
}: {
  imports = [./git.nix];

  config = lib.mkIf config.othrys.system.git.enable {
    programs.git.enable = true;
  };
}
