# flake/templates.nix
# Starting points for a consuming flake, used through `nix flake init -t`
{
  flake.templates.default = {
    path = ../templates/default;
    description = "A minimal NixOS host built from othrys.nix modules";
    welcomeText = ''
      Replace hardware.nix with your own hardware configuration, then set the
      host name, the user, the password hash, an ssh key and stateVersion in
      configuration.nix.

      Build with `nixos-rebuild build --flake .#myhost`.
    '';
  };

  flake.templates.darwin = {
    path = ../templates/darwin;
    description = "A minimal nix-darwin host built from othrys.nix modules, on Lix";
    welcomeText = ''
      Set the host name and the user in configuration.nix. The user is the
      administrator account macOS created at setup.

      nix-darwin manages the Nix installation, and othrys sets Lix as its
      package. Any Nix or Lix installation runs the first switch, which moves
      the daemon to Lix. Switch the first time with
      `sudo nix run --inputs-from . nix-darwin -- switch --flake .#mymac`,
      which takes nix-darwin from this flake's lock, and after that with
      `sudo darwin-rebuild switch --flake .#mymac`.
    '';
  };
}
