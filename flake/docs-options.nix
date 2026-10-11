# flake/docs-options.nix
# Generated options reference, every othrys.* option rendered to CommonMark
# via nixosOptionsDoc and injected into the MdBook build (see flake/checks/
# `docs` and the justfile docs recipe). Zero-drift by construction, since the
# hand-written table this replaces was already missing entire module trees.
# Doubles as a quality gate, since a missing description fails the build.
{inputs, ...}: {
  perSystem = {
    system,
    pkgs,
    lib,
    ...
  }: let
    eval = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = [
        inputs.self.nixosModules.default
        inputs.home-manager.nixosModules.home-manager
        # The reference covers the four exports `default` leaves out too,
        # each beside the upstream module it writes into. The impermanence
        # adapter declares no option of its own. The othrys.system.impermanence
        # options are declared in `default` and are listed either way.
        inputs.self.nixosModules.impermanence
        inputs.impermanence.nixosModules.impermanence
        inputs.self.nixosModules.stylix
        inputs.stylix.nixosModules.stylix
        inputs.self.nixosModules.disko
        inputs.disko.nixosModules.disko
        inputs.self.nixosModules.secrets
        inputs.sops-nix.nixosModules.sops
        {
          boot.loader.grub = {
            enable = true;
            devices = ["nodev"];
          };
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
        }
      ];
    };

    optionsDoc = pkgs.nixosOptionsDoc {
      options = eval.options.othrys;
      transformOptions = opt:
        opt
        // {
          # Store paths would leak build noise into the docs, so link the
          # repo-relative declaration on GitHub instead (declarations outside
          # this flake, e.g. rename aliases, are dropped).
          declarations =
            lib.concatMap (
              d: let
                s = toString d;
                prefix = "${inputs.self}/";
              in
                lib.optional (lib.hasPrefix prefix s) {
                  name = lib.removePrefix prefix s;
                  url = "https://github.com/bippsoft/othrys.nix/blob/main/${lib.removePrefix prefix s}";
                }
            )
            opt.declarations;
        };
    };
  in {
    packages.options-doc = pkgs.runCommand "othrys-options-doc" {} ''
      {
        echo "# Module Options"
        echo
        echo "Every \`othrys.*\` option, generated from the module tree. Do not edit by hand."
        echo
        cat ${optionsDoc.optionsCommonMark}
      } > "$out"
    '';
  };
}
