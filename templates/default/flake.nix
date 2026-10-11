{
  description = "A NixOS host built from othrys.nix modules";

  inputs = {
    othrys.url = "github:bippsoft/othrys.nix";
    nixpkgs.follows = "othrys/nixpkgs";

    # configuration.nix creates a user and leaves Home Manager managing it, so
    # the Home Manager module and inputs.othrys.nixosModules.home are both
    # imported below. Following othrys keeps one copy of it in the lock. A
    # host with no managed user drops this input and both of those imports,
    # and inputs.othrys.nixosModules.default is then all it needs.
    home-manager.follows = "othrys/home-manager";

    # The disk layout, the sops-nix plumbing, the impermanence adapter and the
    # Stylix adapter are separate exports, and this host uses none of them.
    # A host that wants all of them imports inputs.othrys.nixosModules.full in
    # place of the two othrys modules and the Home Manager module below. It
    # is `default` with every export and the upstream module each one
    # configures, taken from the lock of othrys, so nothing is imported
    # beside it and the home-manager input above is not needed.
    #
    # To add one export at a time instead, for the layout add
    # `disko.follows = "othrys/disko";` here and import
    # inputs.othrys.nixosModules.disko beside inputs.disko.nixosModules.disko
    # below. For the plumbing, add `sops-nix.follows = "othrys/sops-nix";` and
    # import inputs.othrys.nixosModules.secrets beside
    # inputs.sops-nix.nixosModules.sops. For an ephemeral root, add
    # `impermanence.follows = "othrys/impermanence";` and import
    # inputs.othrys.nixosModules.impermanence beside
    # inputs.impermanence.nixosModules.impermanence.
  };

  outputs = inputs: {
    nixosConfigurations.myhost = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # othrys reads `inputs.nixpkgs` from here, to pin the flake registry to
      # the revision this host is built from. Pass nothing else.
      specialArgs = {inherit inputs;};
      modules = [
        inputs.othrys.nixosModules.default
        inputs.othrys.nixosModules.home
        inputs.home-manager.nixosModules.home-manager

        ./hardware.nix
        ./configuration.nix
      ];
    };
  };
}
