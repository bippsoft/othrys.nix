# flake/checks/exports-eval.nix
# CORE. The export list in flake/modules.nix, held to the module tree. Every
# infrastructure module file outside modules/apps/ is exported individually,
# and every export names a file or directory that exists. The list fell two
# dozen modules behind the tree once, and nothing noticed, since the
# aggregate `default` evaluated either way.
{
  pkgs,
  inputs,
  moduleHelpers,
}: let
  inherit (inputs.nixpkgs) lib;
  root = toString inputs.self;
  groups = ["system" "desktop" "hardware" "services"];
  relative = path: lib.removePrefix "${root}/" (toString path);
  isModule = path: let
    rel = relative path;
  in
    lib.hasSuffix ".nix" rel && baseNameOf rel != "default.nix" && !(builtins.elem rel moduleHelpers);
  tree = lib.unique (map relative (builtins.filter isModule (lib.concatMap (g: lib.filesystem.listFilesRecursive "${root}/modules/${g}") groups)));
  # flake-parts types the outputs as deferred modules, so each export arrives
  # as a module whose imports hold the path it was declared with, wrapped
  # once per merge level.
  pathsOf = m:
    if builtins.isPath m || builtins.isString m
    then [m]
    else if builtins.isAttrs m
    then lib.concatMap pathsOf (m.imports or [])
    else [];
  exports = lib.mapAttrs (_: pathsOf) (lib.filterAttrs (name: _: name != "default") inputs.self.nixosModules);
  exported = lib.concatMap (map relative) (lib.attrValues exports);
  missing = builtins.filter (f: !(builtins.elem f exported)) tree;
  dangling = lib.attrNames (lib.filterAttrs (_: paths: paths == [] || !(builtins.all builtins.pathExists paths)) exports);
  apps = builtins.filter (f: lib.hasPrefix "modules/apps/" f) exported;
in
  pkgs.runCommand "othrys-eval-exports" {
    missing = builtins.concatStringsSep "\n" missing;
    dangling = builtins.concatStringsSep "\n" dangling;
    apps = builtins.concatStringsSep "\n" apps;
    total = toString (builtins.length tree);
  } ''
    status=0
    if [ -n "$missing" ]; then
      echo "modules not exported in flake/modules.nix:" >&2
      printf '%s\n' "$missing" | sed 's/^/  - /' >&2
      status=1
    fi
    if [ -n "$dangling" ]; then
      echo "exports that name a missing path:" >&2
      printf '%s\n' "$dangling" | sed 's/^/  - /' >&2
      status=1
    fi
    if [ -n "$apps" ]; then
      echo "app modules exported individually:" >&2
      printf '%s\n' "$apps" | sed 's/^/  - /' >&2
      status=1
    fi
    [ "$status" = 0 ] || exit 1
    echo "$total module files exported" > "$out"
  ''
