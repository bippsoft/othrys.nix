# modules/default.nix
# Full module tree, exported as nixosModules.default (flake/modules.nix)
{
  imports = [
    ./system
    ./desktop
    ./hardware
    ./services
    ./apps
  ];
}
