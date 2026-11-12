# flake/checks/project-environment-launcher.nix
# CORE. What the project-environment launcher does when it runs, read back
# from a stand-in agent started in temporary projects. Whether the agent
# starts inside its project's direnv environment exists only at run time, so
# evaluating the launcher proves nothing. The launcher is taken from an
# evaluated host whose codex package is the stand-in, a program that prints
# FOO and exits with the status it is given. A second host sets
# trustWorktrees to false. The host is a NixOS host on
# Linux and a nix-darwin host on a Mac, so the launcher is built for the
# system that runs it.
{
  pkgs,
  hostConfig,
  darwinConfig,
  bootBase,
  darwinBase,
}: let
  standIn = {pkgs, ...}: {
    othrys.apps.ai.codex.package = pkgs.writeShellApplication {
      name = "codex";
      text = ''
        echo "FOO=''${FOO-}"
        exit "''${1:-0}"
      '';
    };
  };
  untrusting = {othrys.apps.ai.projectEnvironment.trustWorktrees = false;};
  host = modules:
    if pkgs.stdenv.hostPlatform.isDarwin
    then darwinConfig ([darwinBase standIn] ++ modules)
    else hostConfig ([bootBase standIn] ++ modules);
  agent = (host []).othrys.internal.agents.codex;
  untrustingAgent = (host [untrusting]).othrys.internal.agents.codex;
in
  pkgs.runCommand "othrys-project-environment-launcher" {
    nativeBuildInputs = [pkgs.direnv pkgs.git pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gnused];
  } ''
    set -euo pipefail
    codex=${agent}/bin/codex
    untrusting=${untrustingAgent}/bin/codex

    # direnv records what is allowed under XDG_DATA_HOME, and git reads its
    # identity from HOME, so both point into the build directory. The path is
    # resolved first, since direnv trusts an .envrc by its path.
    work=$(realpath "$TMPDIR")/work
    export HOME=$work/home
    export XDG_DATA_HOME=$HOME/.local/share XDG_CONFIG_HOME=$HOME/.config XDG_CACHE_HOME=$HOME/.cache
    export GIT_CONFIG_NOSYSTEM=1
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    git config --global user.name alice
    git config --global user.email alice@example.com
    git config --global init.defaultBranch main
    unset FOO DIRENV_DIR DIRENV_FILE DIRENV_DIFF DIRENV_WATCHES

    fail=0
    : > "$work/out"
    : > "$work/err"

    # launch <directory> <exit status> [NAME=value...] starts the launcher in
    # the directory with the status as its argument and the variables set.
    launch() {
      local dir=$1 code=$2
      shift 2
      status=0
      (cd "$dir" && exec env "$@" "$codex" "$code") > "$work/out" 2> "$work/err" || status=$?
    }
    expect() {
      local label=$1
      shift
      if "$@"; then
        echo "ok: $label"
      else
        echo "FAILED: $label" >&2
        sed 's/^/  stdout: /' "$work/out" >&2
        sed 's/^/  stderr: /' "$work/err" >&2
        fail=1
      fi
    }
    printed() { grep -qx "$1" "$work/out"; }
    exited() { [ "$status" = "$1" ]; }
    refused() { grep -q "is not allowed" "$work/err"; }
    notRefused() { ! grep -q "is not allowed" "$work/err"; }
    # direnv reports 0 for an allowed .envrc, 1 for a blocked one and 2 for
    # a denied one.
    allowedState() { (cd "$1" && direnv status --json) | jq -e --argjson want "$2" '.state.foundRC.allowed == $want' > /dev/null; }

    # a. A directory without an .envrc.
    mkdir -p "$work/plain"
    launch "$work/plain" 3
    expect "without an .envrc the program runs with FOO unset" printed "FOO="
    expect "without an .envrc the exit status is passed through" exited 3
    expect "without an .envrc nothing is refused" notRefused

    # b. An allowed .envrc.
    mkdir -p "$work/allowed"
    echo 'export FOO=bar' > "$work/allowed/.envrc"
    (cd "$work/allowed" && direnv allow)
    launch "$work/allowed" 4
    expect "an allowed .envrc sets FOO=bar" printed "FOO=bar"
    expect "with an allowed .envrc the exit status is passed through" exited 4
    expect "an allowed .envrc is not refused" notRefused

    # c. A blocked .envrc outside any git repository.
    mkdir -p "$work/blocked"
    echo 'export FOO=bar' > "$work/blocked/.envrc"
    launch "$work/blocked" 5
    expect "a blocked .envrc leaves FOO unset" printed "FOO="
    expect "a blocked .envrc is named on stderr as not allowed" refused
    expect "with a blocked .envrc the exit status is passed through" exited 5
    expect "a blocked .envrc stays blocked" allowedState "$work/blocked" 1

    # d. A worktree whose .envrc is identical to the allowed main checkout's.
    git init -q "$work/repo"
    echo 'export FOO=bar' > "$work/repo/.envrc"
    git -C "$work/repo" add .envrc
    git -C "$work/repo" commit -qm "add .envrc"
    (cd "$work/repo" && direnv allow)
    git -C "$work/repo" worktree add -q "$work/same"
    expect "a new worktree's identical .envrc starts out blocked" allowedState "$work/same" 1
    launch "$work/same" 6
    expect "an identical worktree .envrc sets FOO=bar" printed "FOO=bar"
    expect "an identical worktree .envrc is not refused" notRefused
    expect "in an identical worktree the exit status is passed through" exited 6
    expect "the identical worktree .envrc is allowed afterwards" allowedState "$work/same" 0

    # e. A worktree whose .envrc differs from the main checkout's.
    git -C "$work/repo" worktree add -q "$work/changed"
    echo 'export FOO=baz' > "$work/changed/.envrc"
    launch "$work/changed" 7
    expect "a changed worktree .envrc leaves FOO unset" printed "FOO="
    expect "a changed worktree .envrc is named on stderr as not allowed" refused
    expect "in a changed worktree the exit status is passed through" exited 7
    expect "the changed worktree .envrc stays blocked" allowedState "$work/changed" 1

    # f. An environment direnv already loaded for the directory, or for one
    # above it. The .envrc there is blocked, so a launcher that consulted
    # direnv would name it on stderr.
    launch "$work/blocked" 8 "DIRENV_DIR=-$work/blocked"
    expect "a loaded environment runs the program directly with FOO unset" printed "FOO="
    expect "a loaded environment consults no .envrc" notRefused
    expect "with a loaded environment the exit status is passed through" exited 8
    mkdir -p "$work/blocked/sub"
    launch "$work/blocked/sub" 9 "DIRENV_DIR=-$work/blocked"
    expect "an environment loaded for a parent directory runs the program directly" notRefused
    launch "$work/blocked" 10 "DIRENV_DIR=-$work/allowed"
    expect "an environment loaded for another directory still consults the .envrc" refused
    mkdir -p "$work/allowed/pkg"
    echo 'export FOO=pkg' > "$work/allowed/pkg/.envrc"
    launch "$work/allowed/pkg" 11 "DIRENV_DIR=-$work/allowed"
    expect "an environment loaded for a parent project still consults a nested .envrc" refused

    # g. A worktree reached through a symlink. direnv trusts the path it
    # reports, which is the logical one, so the allow must go there.
    git -C "$work/repo" worktree add -q "$work/linked"
    ln -s "$work" "$TMPDIR/link"
    launch "$TMPDIR/link/linked" 12
    expect "a worktree reached through a symlink sets FOO=bar" printed "FOO=bar"
    expect "a worktree reached through a symlink is not refused" notRefused
    expect "in a worktree reached through a symlink the exit status is passed through" exited 12

    # h. A worktree whose identical .envrc the user denied.
    git -C "$work/repo" worktree add -q "$work/denied"
    (cd "$work/denied" && direnv deny)
    launch "$work/denied" 13
    expect "a denied worktree .envrc leaves FOO unset" printed "FOO="
    expect "a denied worktree .envrc is named on stderr as not allowed" refused
    expect "a denied worktree .envrc stays denied" allowedState "$work/denied" 2

    # i. A main checkout whose .envrc changed after it was allowed. The
    # worktree matches the new text, which nobody approved.
    echo 'export FOO=qux' > "$work/repo/.envrc"
    git -C "$work/repo" worktree add -q "$work/stale"
    echo 'export FOO=qux' > "$work/stale/.envrc"
    launch "$work/stale" 14
    expect "a worktree matching an unapproved main .envrc leaves FOO unset" printed "FOO="
    expect "a worktree matching an unapproved main .envrc is refused" refused

    # j. With trustWorktrees off, a worktree whose .envrc is identical to
    # the allowed main checkout's. The main .envrc is put back to the
    # approved text first.
    echo 'export FOO=bar' > "$work/repo/.envrc"
    git -C "$work/repo" worktree add -q "$work/untrusted"
    expect "the main .envrc is allowed again before case j" allowedState "$work/repo" 0
    codex=$untrusting
    launch "$work/untrusted" 15
    expect "with trustWorktrees off an identical worktree .envrc leaves FOO unset" printed "FOO="
    expect "with trustWorktrees off an identical worktree .envrc is refused" refused
    expect "with trustWorktrees off the exit status is passed through" exited 15
    expect "with trustWorktrees off the worktree .envrc stays blocked" allowedState "$work/untrusted" 1
    launch "$work/allowed" 16
    expect "with trustWorktrees off an allowed .envrc still sets FOO=bar" printed "FOO=bar"

    [ "$fail" = 0 ] || exit 1
    touch "$out"
  ''
