{
  description = "A nix-darwin host built from othrys.nix modules";

  inputs = {
    othrys.url = "github:bippsoft/othrys.nix";
    nixpkgs.follows = "othrys/nixpkgs";
    nix-darwin.follows = "othrys/nix-darwin";

    # inputs.othrys.darwinModules.full brings Home Manager, Stylix and
    # sops-nix from the lock of othrys, each beside its othrys adapter, so no
    # input of theirs is declared here. A host that wants fewer imports
    # inputs.othrys.darwinModules.default in place of `full`, with
    # inputs.othrys.darwinModules.home beside
    # inputs.home-manager.darwinModules.home-manager and a
    # `home-manager.follows = "othrys/home-manager";` input for the account
    # below.
  };

  outputs = inputs: {
    darwinConfigurations.mymac = inputs.nix-darwin.lib.darwinSystem {
      # othrys reads `inputs.nixpkgs` from here, to pin the flake registry to
      # the revision this host is built from. Pass nothing else.
      specialArgs = {inherit inputs;};
      modules = [
        inputs.othrys.darwinModules.full
        ./configuration.nix
      ];
    };
  };
}
