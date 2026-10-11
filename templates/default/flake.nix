{
  description = "A NixOS host built from othrys.nix modules";

  inputs = {
    othrys.url = "github:bippsoft/othrys.nix";
    nixpkgs.follows = "othrys/nixpkgs";

    # othrys writes into the option namespaces of these two, so their modules
    # are imported below even when the matching othrys feature is off.
    # Following othrys keeps one copy of each in the lock.
    home-manager.follows = "othrys/home-manager";
    impermanence.follows = "othrys/impermanence";

    # The disk layout and the sops-nix plumbing are separate exports, and this
    # host uses neither. For the layout, add `disko.follows = "othrys/disko";`
    # here and import inputs.othrys.nixosModules.disko beside
    # inputs.disko.nixosModules.disko below. For the plumbing, add
    # `sops-nix.follows = "othrys/sops-nix";` and import
    # inputs.othrys.nixosModules.secrets beside
    # inputs.sops-nix.nixosModules.sops.
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
        inputs.impermanence.nixosModules.impermanence

        ./hardware.nix
        ./configuration.nix
      ];
    };
  };
}
