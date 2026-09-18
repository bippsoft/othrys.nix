{
  description = "A NixOS host built from othrys.nix modules";

  inputs = {
    othrys.url = "github:bippsoft/othrys.nix";
    nixpkgs.follows = "othrys/nixpkgs";

    # othrys writes into the option namespaces of these five, so their modules
    # are imported below even when the matching othrys feature is off.
    # Following othrys keeps one copy of each in the lock.
    home-manager.follows = "othrys/home-manager";
    disko.follows = "othrys/disko";
    stylix.follows = "othrys/stylix";
    sops-nix.follows = "othrys/sops-nix";
    impermanence.follows = "othrys/impermanence";
  };

  outputs = inputs: {
    nixosConfigurations.myhost = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # Modules read `inputs` from here. Pass nothing else.
      specialArgs = {inherit inputs;};
      modules = [
        inputs.othrys.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        inputs.disko.nixosModules.disko
        inputs.stylix.nixosModules.stylix
        inputs.sops-nix.nixosModules.sops
        inputs.impermanence.nixosModules.impermanence

        ./hardware.nix
        ./configuration.nix
      ];
    };
  };
}
