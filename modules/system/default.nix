# modules/system/default.nix
# Core system modules, always available and toggled through enable options
#
# disko.nix and secrets.nix sit in this directory and are not imported here.
# Each writes into an option namespace an upstream flake declares, so each is
# exported on its own as nixosModules.disko and nixosModules.secrets
# (flake/modules.nix), and a host imports one together with the upstream
# module it configures.
{
  imports = [
    ./locale.nix
    ./user.nix
    ./users.nix
    ./nix.nix
    ./auto-upgrade.nix
    ./kernel.nix
    ./hardening.nix
    ./impermanence.nix
    ./persistence.nix
    ./bootloader.nix
    ./git.nix
    ./networking.nix
    ./shell
  ];
}
