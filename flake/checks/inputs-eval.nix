# flake/checks/inputs-eval.nix
# CORE. Where the modules take the flakes they build on. ashell, Hyprland,
# nixvim and nix-index-database come from this flake's own lock, handed to
# the modules as the `othrysInputs` argument, so a consumer declares no input
# of those names. The host here is given no specialArgs at all, which is the
# shape that failed on a missing `inputs` argument, and it enables the four
# modules. The packages are read back and compared with the lock, and a
# second host sets each `package` option and is read back the same way.
{
  inputs,
  system,
  upstreamModules,
  secretsModules,
  functioningHost,
  mkExpectations,
}: let
  inherit (inputs.nixpkgs) lib;

  locked = {
    hyprland = inputs.hyprland.packages.${system}.hyprland;
    portal = inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;
    ashell = inputs.ashell.packages.${system}.default;
  };

  theFour = {
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.ashell.enable = true;
    othrys.apps.nixvim.enable = true;
    othrys.apps.comma.enable = true;
  };

  bareEval = extra:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {};
      modules = upstreamModules ++ [functioningHost theFour extra];
    };

  bare = bareEval {};
  # The secrets export names `inputs` as an argument and reads the optional
  # `secrets` input from it, so it is evaluated with no specialArgs as well.
  withSecrets = bareEval {imports = [secretsModules];};
  swapped = bareEval ({pkgs, ...}: {
    othrys.desktop.compositors.hyprland = {
      package = pkgs.hyprland;
      portalPackage = pkgs.xdg-desktop-portal-hyprland;
    };
    othrys.desktop.ashell.package = pkgs.ashell;
  });

  home = evaluation: evaluation.config.home-manager.users.alice;
  pkgsOf = evaluation: evaluation._module.args.pkgs;
  handed = evaluation: lib.subtractLists ["modulesPath"] (builtins.attrNames evaluation._module.specialArgs);

  # Two derivations are the same build when they have the same output path.
  same = a: b: a.outPath == b.outPath;
  installs = evaluation: package: builtins.any (p: (p.outPath or null) == package.outPath) (home evaluation).home.packages;
  # What this flake's module passed to programs.hyprland, before upstream
  # applies its own overrides to the value. hyprland.nix is the one definer.
  passed = evaluation: name: builtins.head evaluation.options.programs.hyprland.${name}.definitions;
  barCommand = evaluation: evaluation.config.systemd.user.services.ashell.serviceConfig.ExecStart;
in
  mkExpectations "othrys-eval-inputs" {
    "the host is handed no specialArgs" = handed bare == [];
    "a host with no specialArgs and the four modules on evaluates" = bare.config.system.build.toplevel.drvPath != null;

    "Hyprland is the locked package" = same (passed bare "package") locked.hyprland;
    "the Hyprland portal is the locked package" = same (passed bare "portalPackage") locked.portal;
    "Home Manager configures the locked Hyprland" = same (home bare).wayland.windowManager.hyprland.package locked.hyprland;
    "the bar's unit starts the locked ashell" = barCommand bare == "${locked.ashell}/bin/ashell";
    "the user's profile installs the locked ashell" = installs bare locked.ashell;
    "nixvim's Home Manager module is imported" = (home bare).programs.nixvim.enable;
    "nixvim imports nixpkgs from the source of the host's package set" = toString (home bare).programs.nixvim.nixpkgs.source == toString (pkgsOf bare).path;
    "nix-index-database's Home Manager module is imported" = (home bare).programs.nix-index-database.comma.enable && (home bare).programs.nix-index.enable;

    "no secrets input reads as an empty set" = withSecrets.config.othrys.system.secrets.secretFiles == {};
    "a host with no inputs gets no registry pin from the nix module" = bare.config.nix.registry.nixpkgs.flake == null;
    "NixOS still pins the registry to the nixpkgs the host was built from" = toString bare.config.nix.registry.nixpkgs.to.path == toString inputs.nixpkgs;

    "a host can set the Hyprland package" = same (passed swapped "package") (pkgsOf swapped).hyprland;
    "a host can set the Hyprland portal package" = same (passed swapped "portalPackage") (pkgsOf swapped).xdg-desktop-portal-hyprland;
    "Home Manager configures the package the host set" = same (home swapped).wayland.windowManager.hyprland.package (pkgsOf swapped).hyprland;
    "a host can set the ashell package" = barCommand swapped == "${(pkgsOf swapped).ashell}/bin/ashell" && installs swapped (pkgsOf swapped).ashell;
    "the package a host set is not the locked one" = !same (passed swapped "package") locked.hyprland;
  }
