# flake/checks/contract-eval.nix
# CORE. Three clauses of the consumer contract, read back from evaluation.
# contract-guards searches the source text for the same clauses, and a search
# reads spelling. An argument set written on one line passes its `username,`
# pattern, a specialArgs set written across several lines passes its
# single-line pattern, and a write to home-manager.users built from a
# variable is not a string the search can find. Here the argument names come
# from builtins.functionArgs, the writers of home-manager.users from the
# locations the module system records for each definition, and the
# specialArgs from the evaluation that received them.
{
  inputs,
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
  # carries the file that made it. Two managed hosts are read, one with the
  # app and desktop modules on and one with the server modules on, so a write
  # behind a module's own enable is a definition here. A file outside this
  # repository belongs to an upstream module and is not held to the rule.
  usersModule = "${root}/modules/system/users.nix";
  writersOf = evaluation: map (definition: toString definition.file) evaluation.options.home-manager.users.definitionsWithLocations;
  inTree = file: lib.hasPrefix "${root}/" file;
  strayWriters = evaluation: builtins.filter (file: inTree file && file != usersModule) (writersOf evaluation);

  managedApps = hostEval [functioningHost appDesktopModules];
  managedServer = hostEval [functioningHost serverModules];
  accountOnly = hostEval [accountNoHomeManager appDesktopModules];

  strays = lib.unique (lib.concatMap strayWriters [managedApps managedServer accountOnly]);

  # Clause 4. nixosSystem adds modulesPath to whatever it is handed, so that
  # name is set aside and the rest has to be `inputs` alone or nothing.
  # eval-inputs (./inputs-eval.nix) evaluates the host that is handed nothing.
  handed = evaluation: lib.subtractLists ["modulesPath"] (builtins.attrNames evaluation._module.specialArgs);
  allowed = evaluation: builtins.elem (handed evaluation) [[] ["inputs"]];

  named = lib.genAttrs (identityArgs ++ map (file: "${relative file} writes home-manager.users") strays) (_: false);
in
  mkExpectations "othrys-eval-contract" (
    named
    // {
      "no module file takes username or hostname as an argument" = identityArgs == [];
      "module files were found to read" = builtins.length moduleFiles > 50;
      "users.nix is recorded as a writer of home-manager.users on a managed host" = builtins.elem usersModule (writersOf managedApps);
      "nothing else in this repository writes home-manager.users" = strays == [];
      "no file in this repository writes home-manager.users on an account-only host" = builtins.filter inTree (writersOf accountOnly) == [];
      "the check fixtures hand a host inputs or nothing" = allowed managedApps;
      "the template hands its host inputs or nothing" = allowed templateHost;
    }
  )
