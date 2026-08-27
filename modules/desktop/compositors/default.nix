# modules/desktop/compositors/default.nix
# Compositor module aggregator
{
  imports = [
    ./hyprland.nix
    ./niri.nix
  ];
}
