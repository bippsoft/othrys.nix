{
  description = "A NixOS host built from othrys.nix modules";

  inputs = {
    othrys.url = "github:bippsoft/othrys.nix";
    nixpkgs.follows = "othrys/nixpkgs";

    # othrys writes into the option namespace of home-manager, so its module
    # is imported below even when no othrys module configures the user.
    # Following othrys keeps one copy of it in the lock.
    home-manager.follows = "othrys/home-manager";

    # The disk layout, the sops-nix plumbing and the impermanence adapter are
    # separate exports, and this host uses none of them. For the layout, add
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
        inputs.home-manager.nixosModules.home-manager

        ./hardware.nix
        ./configuration.nix
      ];
    };
  };
}
