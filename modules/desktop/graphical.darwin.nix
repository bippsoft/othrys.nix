# modules/desktop/graphical.darwin.nix
# The nix-darwin implementation of othrys.desktop.graphical
{lib, ...}: {
  imports = [./graphical.nix];

  # macOS always runs its own graphical session, which no othrys compositor
  # module manages, so the flag is on unless the host says otherwise.
  config.othrys.desktop.graphical = lib.mkDefault true;
}
