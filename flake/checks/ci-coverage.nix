# flake/checks/ci-coverage.nix
# CORE. The check names in .github/workflows/build.yml, held to the checks this
# flake defines. The workflow lists its checks by name, so a check registered
# here and left out there is built by no job and stays green whatever it would
# have said. The comparison runs both ways, since a name the workflow lists
# and the flake no longer defines fails the job that builds it, and it runs
# for every system the flake defines checks for.
{
  pkgs,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;
  workflow = builtins.readFile ../../.github/workflows/build.yml;

  # Every system the flake defines checks for. Each is read on its own, so
  # a check defined for aarch64-darwin is held to a job that builds it for
  # aarch64-darwin, and a name built for x86_64-linux does not cover it.
  systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

  # Checks no job builds by name, each for a stated reason. An entry that a
  # job does list, or that names no check, fails below as a stale exclusion.
  localOnly = {
    x86_64-linux = [
      # pre-commit-check runs the same two applications as hooks over the
      # whole tree. The standalone checks give `nix flake check` a failure
      # that names the convention instead of the hook runner.
      "comment-hygiene"
      "contract-guards"
      # Registered by the treefmt-nix flake module. pre-commit-check runs
      # the same treefmt wrapper as its first hook.
      "treefmt"
    ];
    # The treefmt-nix flake module registers it on every system. Formatting
    # does not vary by platform, and the x86_64-linux and aarch64-darwin
    # jobs already run it.
    aarch64-linux = ["treefmt"];
    aarch64-darwin = [];
  };

  # Reading the attribute names does not force any check.
  defined = system: builtins.attrNames inputs.self.checks.${system};

  # builtins.split returns the text between matches as strings and each
  # match as the list of its groups.
  captures = regex: text: map builtins.head (builtins.filter builtins.isList (builtins.split regex text));

  # The core jobs name each check as an installable. An extended job's
  # build line interpolates the matrix variable, which this does not match.
  byInstallable = system: captures "checks\\.${system}\\.([A-Za-z0-9_-]+)" workflow;

  # An extended job names its checks as the items of matrix.check. Each
  # block is read from the line after that key up to the first line that is
  # not a bare list item, and its system is the one named in the first
  # build line after it that interpolates the matrix variable.
  blocks = builtins.tail (builtins.filter builtins.isString (builtins.split "matrix:[[:space:]]+check:\n" workflow));
  item = line: builtins.match "[[:space:]]+- ([A-Za-z0-9_-]+)" line;
  itemsOf = block:
    (builtins.foldl' (
        acc: line:
          if acc.done || item line == null
          then acc // {done = true;}
          else acc // {names = acc.names ++ item line;}
      ) {
        done = false;
        names = [];
      } (lib.splitString "\n" block)).names;
  systemOf = block: builtins.head (captures "checks\\.([A-Za-z0-9_-]+)\\.\\$\\{\\{ matrix\\.check" block ++ [null]);
  byMatrix = system: lib.concatMap itemsOf (builtins.filter (block: systemOf block == system) blocks);

  listed = system: lib.unique (byInstallable system ++ byMatrix system);

  report = f: lib.concatMap (system: map (name: "${system}.${name}") (f system)) systems;
  unbuilt = report (system: builtins.filter (name: !(builtins.elem name (listed system)) && !(builtins.elem name localOnly.${system})) (defined system));
  undefined = report (system: builtins.filter (name: !(builtins.elem name (defined system))) (listed system));
  staleExclusions = report (system: builtins.filter (name: !(builtins.elem name (defined system)) || builtins.elem name (listed system)) localOnly.${system});
  unreadBlocks = builtins.filter (block: systemOf block == null) blocks;
  total = builtins.foldl' (n: system: n + builtins.length (listed system)) 0 systems;
in
  pkgs.runCommand "othrys-ci-coverage" {
    unbuilt = builtins.concatStringsSep "\n" unbuilt;
    undefined = builtins.concatStringsSep "\n" undefined;
    staleExclusions = builtins.concatStringsSep "\n" staleExclusions;
    unreadBlocks = toString (builtins.length unreadBlocks);
    matrices = toString (builtins.length blocks);
    total = toString total;
  } ''
    status=0
    if [ -n "$unbuilt" ]; then
      echo "checks that no job in .github/workflows/build.yml builds:" >&2
      printf '%s\n' "$unbuilt" | sed 's/^/  - /' >&2
      status=1
    fi
    if [ -n "$undefined" ]; then
      echo "names in .github/workflows/build.yml that are not checks:" >&2
      printf '%s\n' "$undefined" | sed 's/^/  - /' >&2
      status=1
    fi
    if [ -n "$staleExclusions" ]; then
      echo "localOnly entries that a job builds, or that name no check:" >&2
      printf '%s\n' "$staleExclusions" | sed 's/^/  - /' >&2
      status=1
    fi
    if [ "$unreadBlocks" != 0 ]; then
      echo "$unreadBlocks matrix.check lists with no build line naming a system" >&2
      status=1
    fi
    [ "$status" = 0 ] || exit 1
    echo "$total checks built by name, from $matrices matrices" > "$out"
  ''
