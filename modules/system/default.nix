# modules/system/default.nix
# Core system modules, always available and toggled through enable options
#
# home.nix, disko.nix, secrets.nix and impermanence.nix sit in this directory
# and are not imported here. Each writes into an option namespace an upstream
# flake declares, so each is exported on its own as nixosModules.home,
# nixosModules.disko, nixosModules.secrets and nixosModules.impermanence
# (flake/modules.nix), and a host imports one together with the upstream
# module it configures.
{
  imports = [
    ./locale.nixos.nix
    ./user.nix
    ./users.nixos.nix
    ./nix.nixos.nix
    ./auto-upgrade.nix
    ./kernel.nix
    ./hardening.nix
    ./ephemeral-root.nix
    ./persistence.nixos.nix
    ./bootloader.nix
    ./git.nixos.nix
    ./networking.nix
    ./shell
  ];
}
