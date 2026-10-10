# flake/checks/ci-coverage.nix
# CORE. The check names in .github/workflows/build.yml, held to the checks this
# flake defines. The workflow lists its checks by name, so a check registered
# here and left out there is built by no job and stays green whatever it would
# have said. The comparison runs both ways, since a name the workflow lists
# and the flake no longer defines fails the job that builds it.
{
  pkgs,
  inputs,
  system,
}: let
  inherit (inputs.nixpkgs) lib;
  workflow = builtins.readFile ../../.github/workflows/build.yml;

  # Checks no job builds by name, each for a stated reason. An entry that a
  # job does list, or that names no check, fails below as a stale exclusion.
  localOnly = [
    # pre-commit-check runs the same two applications as hooks over the whole
    # tree. The standalone checks give `nix flake check` a failure that names
    # the convention instead of the hook runner.
    "comment-hygiene"
    "contract-guards"
    # Registered by the treefmt-nix flake module. pre-commit-check runs the
    # same treefmt wrapper as its first hook.
    "treefmt"
  ];

  # Reading the attribute names does not force any check.
  defined = builtins.attrNames inputs.self.checks.${system};

  # builtins.split returns the text between matches as strings and each
  # match as the list of its groups.
  captures = regex: text: map builtins.head (builtins.filter builtins.isList (builtins.split regex text));

  # The core job names each check as an installable. The extended job's
  # build line interpolates the matrix variable, which this does not match.
  byInstallable = captures "checks\\.x86_64-linux\\.([A-Za-z0-9_-]+)" workflow;

  # The extended job names its checks as the items of matrix.check. The
  # items are read from the line after that key up to the first line that
  # is not a bare list item.
  afterMatrix = lib.last (builtins.split "matrix:[[:space:]]+check:\n" workflow);
  item = line: builtins.match "[[:space:]]+- ([A-Za-z0-9_-]+)" line;
  byMatrix =
    (builtins.foldl' (
        acc: line:
          if acc.done || item line == null
          then acc // {done = true;}
          else acc // {names = acc.names ++ item line;}
      ) {
        done = false;
        names = [];
      } (lib.splitString "\n" afterMatrix)).names;

  listed = lib.unique (byInstallable ++ byMatrix);

  unbuilt = builtins.filter (name: !(builtins.elem name listed) && !(builtins.elem name localOnly)) defined;
  undefined = builtins.filter (name: !(builtins.elem name defined)) listed;
  staleExclusions = builtins.filter (name: !(builtins.elem name defined) || builtins.elem name listed) localOnly;
in
  pkgs.runCommand "othrys-ci-coverage" {
    unbuilt = builtins.concatStringsSep "\n" unbuilt;
    undefined = builtins.concatStringsSep "\n" undefined;
    staleExclusions = builtins.concatStringsSep "\n" staleExclusions;
    total = toString (builtins.length listed);
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
    [ "$status" = 0 ] || exit 1
    echo "$total checks built by name" > "$out"
  ''
