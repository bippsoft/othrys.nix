# modules/apps/gui/ghostty.nixos.nix
# The NixOS implementation of othrys.apps.ghostty, which picks the Linux package
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./ghostty.nix];

  config = lib.mkIf config.othrys.apps.ghostty.enable {
    othrys.internal.homeConfig."apps.ghostty.package".programs.ghostty.package = lib.mkDefault pkgs.ghostty;
  };
}
