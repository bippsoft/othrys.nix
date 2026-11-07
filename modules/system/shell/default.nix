# modules/system/shell/default.nix
# Shell module aggregator
{
  imports = [
    ./editor.nixos.nix
    ./bash.nix
    ./zsh.nixos.nix
    ./starship.nix
  ];
}
