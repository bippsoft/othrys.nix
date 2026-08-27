# flake/treefmt.nix
# Multi-language formatting via treefmt-nix.
#
# The treefmt-nix flake module automatically wires up `nix fmt` (formatter) and a
# treefmt flake check. The pre-commit hook (flake/checks/, flake/dev-shells.nix)
# reuses `config.treefmt.build.wrapper` so local and CI formatting are identical.
#
# Nix linting (statix, deadnix) stays as separate pre-commit hooks, since they lint
# rather than format, so they are intentionally not run as treefmt formatters.
_: {
  perSystem = _: {
    treefmt = {
      # Anchor on the lockfile. `.git/config` looked equivalent and is not, since
      # in a `git worktree` checkout `.git` is a file rather than a directory and
      # treefmt then finds no root at all.
      projectRootFile = "flake.lock";

      programs = {
        alejandra.enable = true; # Nix
        # Shell formatting only. Shellcheck linting is done by the script's
        # writeShellApplication package (treefmt's shellcheck is stricter and
        # flags intentional patterns like printing literal Nix "${username}").
        shfmt.enable = true; # Shell
        taplo.enable = true; # TOML
        yamlfmt.enable = true; # YAML
        mdformat = {
          enable = true; # Markdown
          # mdbook source carries custom {{#include}}, anchors and nav that
          # mdformat rewrites. Agent skill files carry YAML frontmatter, which
          # it turns into a horizontal rule plus a heading, breaking skill
          # loading entirely. This repository ships no skills, so the second
          # glob is defensive for consumers who vendor their own.
          excludes = [
            "docs/**"
            "**/skills/**"
          ];
        };
      };

      settings.excludes = [
        "*.svg"
        "*.png"
        "*.jpg"
        "*.ico"
        "*.woff2"
        "*.dhall" # no dhall formatter configured
        ".envrc" # direnv stub: no shebang, triggers shellcheck SC2148
        ".envrc.local"
        "assets/**"
        "docs/book/**" # built mdbook output
      ];
    };
  };
}
