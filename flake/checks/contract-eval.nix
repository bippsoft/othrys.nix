# flake/checks/contract-eval.nix
# CORE. Three clauses of the consumer contract, read back from evaluation.
# contract-guards searches the source text for the same clauses, and a search
# reads spelling. An argument set written on one line passes its `username,`
# pattern, a specialArgs set written across several lines passes its
# single-line pattern, and a write to home-manager.users or to
# environment.persistence built from a variable is not a string the search
# can find. Here the argument names come from builtins.functionArgs, the
# writers of home-manager.users and of environment.persistence from the
# locations the module system records for each definition, and the
# specialArgs from the evaluation that received them.
{
  inputs,
  impermanenceModules,
  homeModules,
  hostEval,
  mkExpectations,
  templateHost,
  moduleHelpers,
  functioningHost,
  accountNoHomeManager,
  appDesktopModules,
  serverModules,
}: let
  inherit (inputs.nixpkgs) lib;
  root = toString inputs.self;
  relative = path: lib.removePrefix "${root}/" (toString path);

  # Clause 1. A module file is a function of its arguments, and functionArgs
  # names them however the set is laid out. A helper is handed its arguments
  # by the module that imports it, so the helpers are left out.
  forbiddenArgs = ["username" "hostname"];
  moduleFiles =
    builtins.filter (file: lib.hasSuffix ".nix" file && !(builtins.elem (relative file) moduleHelpers))
    (map toString (lib.filesystem.listFilesRecursive "${root}/modules"));
  argsOf = file: let
    value = import file;
  in
    if builtins.isFunction value
    then builtins.attrNames (builtins.functionArgs value)
    else [];
  identityArgs =
    lib.concatMap (
      file:
        map (arg: "${relative file} takes ${arg} as a module argument")
        (builtins.filter (arg: builtins.elem arg forbiddenArgs) (argsOf file))
    )
    moduleFiles;

  # Clause 2, home-manager half. Every definition of home-manager.users
  # carries the file that made it, and the one file allowed to make one is
  # the export, nixosModules.home. Two managed hosts are read, one with the
  # app and desktop modules on and one with the server modules on, so a write
  # behind a module's own enable is a definition here. A file outside this
  # repository belongs to an upstream module and is not held to the rule.
  homeModule = "${root}/modules/system/home.nix";
  writersOf = evaluation: map (definition: toString definition.file) evaluation.options.home-manager.users.definitionsWithLocations;
  inTree = file: lib.hasPrefix "${root}/" file;
  strayWriters = evaluation: builtins.filter (file: inTree file && file != homeModule) (writersOf evaluation);

  # Both managed hosts wipe their root, so the same two evaluations show who
  # writes environment.persistence. No disk layout is imported. The device is
  # named by hand, and the secrets module, which both fixtures enable, asks
  # for the persisted ssh host key and a running sshd.
  wiped = {
    imports = [impermanenceModules];
    fileSystems = {
      "/nix" = {
        device = "/dev/disk/by-label/nix";
        fsType = "btrfs";
      };
      "/persist" = {
        device = "/dev/disk/by-label/persist";
        fsType = "btrfs";
      };
    };
    othrys = {
      system = {
        impermanence = {
          enable = true;
          device = "/dev/disk/by-partlabel/root";
        };
        persistence.enable = true;
      };
      services.ssh = {
        enable = true;
        server.enable = true;
      };
    };
  };

  managedApps = hostEval [functioningHost appDesktopModules wiped];
  managedServer = hostEval [functioningHost serverModules wiped];
  # The account Home Manager does not manage, with the Home Manager module
  # and the export imported all the same, so the option exists to be read and
  # the export is shown to write nothing into it.
  accountOnly = hostEval [accountNoHomeManager homeModules appDesktopModules];

  strays = lib.unique (lib.concatMap strayWriters [managedApps managedServer accountOnly]);

  # Clause 2, persistence half. Every module names its persistent paths in
  # othrys.internal.persist, and the impermanence adapter is the one file
  # that hands them to the impermanence module. A module behind its own
  # enable is a definition on one of the two hosts above. A file outside this
  # repository is the host's own configuration and is not held to the rule.
  adapterModule = "${root}/modules/system/impermanence.nix";
  persistWritersOf = evaluation: map (definition: toString definition.file) evaluation.options.environment.persistence.definitionsWithLocations;
  strayPersistWriters = evaluation: builtins.filter (file: inTree file && file != adapterModule) (persistWritersOf evaluation);
  persistStrays = lib.unique (lib.concatMap strayPersistWriters [managedApps managedServer]);
  registryKeys = evaluation: builtins.attrNames evaluation.config.othrys.internal.persist;

  # Clause 4. nixosSystem adds modulesPath to whatever it is handed, so that
  # name is set aside and the rest has to be `inputs` alone or nothing.
  # eval-inputs (./inputs-eval.nix) evaluates the host that is handed nothing.
  handed = evaluation: lib.subtractLists ["modulesPath"] (builtins.attrNames evaluation._module.specialArgs);
  allowed = evaluation: builtins.elem (handed evaluation) [[] ["inputs"]];

  named = lib.genAttrs (
    identityArgs
    ++ map (file: "${relative file} writes home-manager.users") strays
    ++ map (file: "${relative file} writes environment.persistence") persistStrays
  ) (_: false);
in
  mkExpectations "othrys-eval-contract" (
    named
    // {
      "no module file takes username or hostname as an argument" = identityArgs == [];
      "module files were found to read" = builtins.length moduleFiles > 50;
      "the export is recorded as a writer of home-manager.users on a managed host" = builtins.elem homeModule (writersOf managedApps);
      "nothing else in this repository writes home-manager.users" = strays == [];
      "no file in this repository writes home-manager.users on an account-only host" = builtins.filter inTree (writersOf accountOnly) == [];
      "the adapter is recorded as a writer of environment.persistence on the app host" = builtins.elem adapterModule (persistWritersOf managedApps);
      "the adapter is recorded as a writer of environment.persistence on the server host" = builtins.elem adapterModule (persistWritersOf managedServer);
      "nothing else in this repository writes environment.persistence" = persistStrays == [];
      "the app and desktop modules reach the adapter through the registry" = builtins.all (key: builtins.elem key (registryKeys managedApps)) ["apps.gh" "apps.gaming.steam" "system.persistence"];
      "the server modules reach the adapter through the registry" = builtins.all (key: builtins.elem key (registryKeys managedServer)) ["services.tailscale" "services.grafana" "services.containerization.docker"];
      "the check fixtures hand a host inputs or nothing" = allowed managedApps;
      "the template hands its host inputs or nothing" = allowed templateHost;
    }
  )
