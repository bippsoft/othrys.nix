# Linting & Formatting

Eight hooks run on every commit once the dev shell has installed them, and the
`pre-commit-check` flake check runs the same set in CI. Both are built from the
two hook sets named in `flake/checks/default.nix`.

## Hooks

| Hook | Purpose | Hook stage | Run by hand |
|------|---------|------------|-------------|
| **treefmt** | Formats Nix (Alejandra), shell (shfmt), TOML (taplo), YAML (yamlfmt) and Markdown (mdformat) | `pre-commit` | `just fmt` |
| **Statix** | Nix linter (anti-patterns) | `pre-commit` | `just lint` |
| **Deadnix** | Dead code detector | `pre-commit` | `just lint` |
| **commitizen** | Conventional commit message validation | `commit-msg` | `cz check` |
| **gitleaks** | Scans what the commit stages for keys and tokens | `pre-commit` | |
| **comment-hygiene** | File headers, banner comments, anchors, and docs pages and links | `pre-commit` | |
| **contract-mirror** | Keeps the consumer contract in `CONTRIBUTING.md` and `CLAUDE.md` identical | `pre-commit` | |
| **contract-guards** | Enforces the consumer contract against `modules/` | `pre-commit` | |

The first five suit any Nix repository, and `devShells.consumer` installs
those alone. The last three read this repository's own tree, so only
`devShells.default` installs them.

Alejandra is not a hook of its own. It runs as one of the treefmt formatters,
which are configured in `flake/treefmt.nix`. mdformat skips `docs/` and
`CHANGELOG.md`.

`secret-scan` is a separate flake check that runs gitleaks over every tracked
file, where the hook sees only what one commit stages.

## Commit Messages

commitizen enforces the [Conventional Commits](https://www.conventionalcommits.org/) format.

```
type(scope): description

# Examples:
feat: add ashell status bar module
fix: resolve GPU adapter failure with Vulkan backend
chore: update flake inputs
docs: add keybindings reference
```

Valid types: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `revert`.

Hooks are built in `flake/dev-shells.nix` with `git-hooks.nix` and installed when entering the dev shell (`nix develop`).

## Manual Checks

```bash
# Format the repository
just fmt

# Format check, statix and deadnix
just lint

# lint plus nix flake check
just ci
```

`just lint` runs statix and deadnix from the dev shell. `nix run nixpkgs#statix`
resolves through the flake registry and not through `flake.lock`, so it can run
a different version than CI and the hook do.

## Fixing Issues

- **Formatting**: `just fmt` auto-fixes all formatting
- **Statix**: Read the suggestions and apply them by hand, or run `nix develop -c statix fix .`
- **Deadnix**: Remove unused variables/arguments flagged by deadnix
