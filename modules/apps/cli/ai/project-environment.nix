# modules/apps/cli/ai/project-environment.nix
# Starts each coding agent inside the direnv environment of its project
#
# An agent started by a daemon, an editor or a shell outside the project
# inherits that launcher's environment, so its hooks and its commands miss
# the project's own tools. The launcher here runs `claude` and `codex`
# through `direnv exec` when the directory they start in has an allowed
# .envrc, and runs them unchanged otherwise. Every module that installs or
# runs one of the agents reads the package from othrys.internal.agents.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.projectEnvironment;
  aiCfg = config.othrys.apps.ai;

  # The launcher replaces one program of the package and runs the original
  # by its store path. A build that finds no program fails, so a renamed
  # binary cannot skip the launcher unnoticed.
  wrap = base: let
    program = base.meta.mainProgram or base.pname;
    launcher = pkgs.writeShellScript "${program}-project-environment" ''
      real=${base}/bin/${program}
      direnv=${pkgs.direnv}/bin/direnv
      jq=${pkgs.jq}/bin/jq
      git=${pkgs.git}/bin/git
      realpath=${pkgs.coreutils}/bin/realpath

      status=$("$direnv" status --json 2>/dev/null) || exec "$real" "$@"
      rc=$("$jq" -r '.state.foundRC.path // empty' <<<"$status")
      [ -n "$rc" ] || exec "$real" "$@"
      allowed=$("$jq" -r '.state.foundRC.allowed' <<<"$status")

      # The environment direnv already loaded for this .envrc, as in a shell
      # inside the project or an agent started by another. An environment
      # loaded for a different .envrc, such as a parent project's, is not it.
      if [ -n "''${DIRENV_DIR:-}" ] && [ "''${DIRENV_DIR#-}" = "''${rc%/*}" ]; then
        exec "$real" "$@"
      fi

      ${lib.optionalString cfg.trustWorktrees ''
        # direnv trusts an .envrc by its path, so a new git worktree of an
        # allowed checkout starts out blocked. The worktree's file is allowed
        # when it is identical to the main checkout's file at the same place
        # and that one is allowed, which extends trust only to text the user
        # already approved. Paths are resolved for the comparisons alone, and
        # the allow goes to the path direnv reported, which is the one its
        # exec looks up again.
        if [ "$allowed" = 1 ]; then
          common=$("$git" -C "$PWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=
          top=$("$git" -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || top=
          if [ -n "$common" ] && [ -n "$top" ] && [ "''${common##*/}" = .git ]; then
            mainLogical=''${common%/.git}
            main=$("$realpath" "$mainLogical")
            top=$("$realpath" "$top")
            rcReal=$("$realpath" "$rc")
            relative=''${rcReal#"$top"/}
            source="$main/$relative"
            if [ "$main" != "$top" ] && [ "$relative" != "$rcReal" ] && [ -f "$source" ] \
              && ${pkgs.diffutils}/bin/cmp -s "$rcReal" "$source"; then
              mainStatus=$(cd "$mainLogical/''${relative%.envrc}" && "$direnv" status --json 2>/dev/null) || mainStatus=
              mainRc=$("$jq" -r '.state.foundRC.path // empty' <<<"$mainStatus" 2>/dev/null) || mainRc=
              mainAllowed=$("$jq" -r '.state.foundRC.allowed // empty' <<<"$mainStatus" 2>/dev/null) || mainAllowed=
              if [ -n "$mainRc" ] && [ "$("$realpath" "$mainRc")" = "$source" ] && [ "$mainAllowed" = 0 ] \
                && "$direnv" allow "$rc" 2>/dev/null; then
                status=$("$direnv" status --json 2>/dev/null) || status=
                allowed=$("$jq" -r '.state.foundRC.allowed // empty' <<<"$status" 2>/dev/null) || allowed=
              fi
            fi
          fi
        fi
      ''}

      # The directory of the .envrc direnv reported, so the exec looks up the
      # same path the status and the allow did. direnv exec leaves the
      # working directory as it is.
      if [ "$allowed" = 0 ]; then
        exec "$direnv" exec "''${rc%/*}" "$real" "$@"
      fi

      # direnv exec refuses a blocked .envrc without running the command, so
      # the agent starts as it would without the launcher.
      echo "othrys: $rc is not allowed, so ${program} starts without its environment. Run direnv allow to load it." >&2
      exec "$real" "$@"
    '';
  in
    pkgs.symlinkJoin {
      pname = base.pname or program;
      version = base.version or "unversioned";
      paths = [base];
      postBuild = ''
        if [ ! -e "$out/bin/${program}" ]; then
          echo "othrys.apps.ai.projectEnvironment: no ${program} program in ${base}" >&2
          exit 1
        fi
        rm "$out/bin/${program}"
        ln -s ${launcher} "$out/bin/${program}"
      '';
      passthru =
        (base.passthru or {})
        // {
          unwrapped = base;
          inherit launcher;
        };
      # Only the out output is joined, so an output the base installs beside
      # it is not one the wrapper has.
      meta = removeAttrs (base.meta or {}) ["outputsToInstall"] // {mainProgram = program;};
    };

  package = base:
    if cfg.enable
    then wrap base
    else base;
in {
  options.othrys.apps.ai.projectEnvironment = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start `claude` and `codex` through `direnv exec` when the directory
        they start in has an allowed `.envrc`, so their hooks and commands
        see the project's environment whichever program started them. A
        directory without an `.envrc` and an environment direnv already
        loaded leave the agent unchanged.
      '';
    };

    trustWorktrees = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When an agent starts in a git worktree, run `direnv allow` on its
        `.envrc` when it is identical to the allowed `.envrc` at the same
        place in the main checkout. The allow is written to the user's
        direnv allow store, so it outlasts the agent and a shell in the
        worktree loads the file too. When false, a new worktree's `.envrc`
        stays blocked until the user allows it. Has no effect while
        `enable` is off.
      '';
    };
  };

  options.othrys.internal.agents = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    internal = true;
    readOnly = true;
    description = ''
      The `claude-code` and `codex` packages every module installs or runs,
      wrapped by the launcher while othrys.apps.ai.projectEnvironment.enable
      is set.
    '';
  };

  config.othrys.internal.agents = {
    claude-code = package aiCfg.claude-code.package;
    codex = package aiCfg.codex.package;
  };
}
