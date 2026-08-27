# modules/system/default.nix
# Core system modules, always available and toggled through enable options
{
  imports = [
    ./locale.nix
    ./user.nix
    ./users.nix
    ./nix.nix
    ./auto-upgrade.nix
    ./kernel.nix
    ./impermanence.nix
    ./persistence.nix
    ./bootloader.nix
    ./disko.nix
    ./secrets.nix
    ./git.nix
    ./networking.nix
    ./shell
    ./stylix.nix
  ];
}
