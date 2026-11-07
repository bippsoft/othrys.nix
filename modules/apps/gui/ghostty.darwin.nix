# modules/apps/gui/ghostty.darwin.nix
# The darwin implementation of othrys.apps.ghostty, which picks the macOS release
{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./ghostty.nix];

  # ghostty-bin keeps its resources inside the app bundle and copies the Vim
  # files to its `vim` output, and Home Manager reads the bat syntax from the
  # bundle on darwin, so the syntax toggles work with it as they do on Linux.
  config = lib.mkIf config.othrys.apps.ghostty.enable {
    othrys.internal.homeConfig."apps.ghostty.package".programs.ghostty.package = lib.mkDefault pkgs.ghostty-bin;
  };
}
