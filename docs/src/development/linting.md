# Linting & Formatting

Four tools enforce code quality, running automatically via git hooks.

## Tools

| Tool | Purpose | Hook stage | Command |
|------|---------|------------|---------|
| **Alejandra** | Nix formatter | `pre-commit` | `just fmt` |
| **Statix** | Nix linter (anti-patterns) | `pre-commit` | `nix run nixpkgs#statix -- check .` |
| **Deadnix** | Dead code detector | `pre-commit` | `nix run nixpkgs#deadnix -- .` |
| **Commitizen** | Conventional commit message validation | `commit-msg` | `cz check` |

## Git Hooks

The first three run on `pre-commit` (file changes). Commitizen runs on `commit-msg` and enforces [Conventional Commits](https://www.conventionalcommits.org/) format:

```
type(scope): description

# Examples:
feat: add ashell status bar module
fix: resolve GPU adapter failure with Vulkan backend
chore: update flake inputs
docs: add keybindings reference
```

Valid types: `feat`, `fix`, `chore`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `revert`.

Hooks are configured in `flake/dev-shells.nix` via `git-hooks.nix` and installed when entering the dev shell (`nix develop`).

## Manual Checks

```bash
# Format all Nix files
just fmt

# Run all linters
just lint

# Full CI suite (lint + check + build)
just ci
```

## Fixing Issues

- **Formatting**: `just fmt` auto-fixes all formatting
- **Statix**: Review suggestions and apply manually (or `nix run nixpkgs#statix -- fix .`)
- **Deadnix**: Remove unused variables/arguments flagged by deadnix
