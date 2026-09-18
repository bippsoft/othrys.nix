# flake/templates.nix
# Starting points for a consuming flake, used through `nix flake init -t`
{
  flake.templates.default = {
    path = ../templates/default;
    description = "A minimal NixOS host built from othrys.nix modules";
    welcomeText = ''
      Replace hardware.nix with your own hardware configuration, then set the
      host name, the user and stateVersion in configuration.nix.

      Build with `nixos-rebuild build --flake .#myhost`.
    '';
  };
}
