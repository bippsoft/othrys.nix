# flake/docs-options.nix
# Generated options reference, every othrys.* option rendered to CommonMark
# via nixosOptionsDoc and injected into the MdBook build (see flake/checks/
# `docs` and the justfile docs recipe). Zero-drift by construction, since the
# hand-written table this replaces was already missing entire module trees.
# Doubles as a quality gate, since a missing description fails the build.
# The options of darwinModules.full are read from a darwinSystem evaluation
# beside the NixOS one, and each option names the platforms that declare it.
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
        # The reference covers the five exports `default` leaves out too,
        # each beside the upstream module it writes into. The Home Manager
        # and impermanence adapters declare no option of their own. The
        # othrys.system.users and othrys.system.impermanence options are
        # declared in `default` and are listed either way.
        inputs.self.nixosModules.home
        inputs.home-manager.nixosModules.home-manager
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

    # The darwin tree with every darwin adapter and its upstream module. The
    # evaluation reads option declarations alone, so it runs on Linux.
    darwinEval = inputs.nix-darwin.lib.darwinSystem {
      specialArgs = {inherit inputs;};
      modules = [
        inputs.self.modules.darwin.full
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.stateVersion = 6;
        }
      ];
    };
    namesOf = options: map (opt: opt.name) (lib.optionAttrSetToDocList options);
    nixosNames = namesOf eval.options.othrys;
    darwinNames = namesOf darwinEval.options.othrys;

    # The two trees, with every option either declares. Where both declare
    # one, the NixOS declaration is the one rendered.
    union = nixos: darwin:
      if lib.isOption nixos || lib.isOption darwin
      then nixos
      else
        nixos
        // lib.mapAttrs (name: value:
          if nixos ? ${name}
          then union nixos.${name} value
          else value)
        darwin;
    platformsOf = name:
      if !(builtins.elem name darwinNames)
      then "NixOS only"
      else if builtins.elem name nixosNames
      then "NixOS and nix-darwin"
      else "nix-darwin only";

    # union keeps the NixOS side whole wherever either platform declares an
    # option, so a darwin option below such a path would be left out. Every
    # darwin name has to come through, or the build stops and names it.
    dropped = lib.subtractLists (namesOf (union eval.options.othrys darwinEval.options.othrys)) darwinNames;

    optionsDoc = assert lib.assertMsg (dropped == []) "options-doc: the union of the option trees drops these darwin options: ${lib.concatStringsSep ", " dropped}";
      pkgs.nixosOptionsDoc {
        options = union eval.options.othrys darwinEval.options.othrys;
        transformOptions = opt:
          opt
          // {
            description =
              if builtins.isString opt.description
              then opt.description + "\n\n*Platforms:* ${platformsOf opt.name}."
              else opt.description;
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
    # The reference is rendered from a NixOS evaluation, which a darwin
    # system cannot run, so only the Linux systems have it.
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      options-doc = pkgs.runCommand "othrys-options-doc" {} ''
        {
          echo "# Module Options"
          echo
          echo "Every \`othrys.*\` option, generated from the module tree. Do not edit by hand. Each option names the platforms that declare it, and one declared on nix-darwin is in \`darwinModules.default\` or one of the darwin adapters."
          echo
          cat ${optionsDoc.optionsCommonMark}
        } > "$out"
      '';
    };
  };
}
