# Flake Inputs

All external dependencies are declared in `flake.nix`:

```nix
{{#include ../../../flake.nix:inputs}}
```

## Input Summary

| Input | Purpose |
|-------|---------|
| `ashell` | GPU-accelerated Wayland status bar (used by the ashell status-bar module) |
| `nixpkgs` | Main package set (unstable channel) |
| `flake-parts` | Modular flake framework |
| `home-manager` | Declarative user environment management |
| `hyprland` | Wayland compositor (pinned, not following nixpkgs) |
| `disko` | Declarative disk partitioning |
| `nix-index-database` | Prebuilt database for `comma` and `nix-locate` |
| `impermanence` | Opt-in state persistence |
| `nixvim` | Neovim configuration via Nix modules (used by the nixvim module) |
| `stylix` | System-wide base16 theming |
| `nixos-hardware` | Hardware-specific optimizations |
| `git-hooks` | Pre-commit validation (treefmt, Statix, Deadnix) |
| `treefmt-nix` | Multi-language formatter behind `nix fmt` |
| `sops-nix` | Secrets management with age encryption |

The private `secrets` input is declared only in the consuming fleet flake, never here, since this flake must remain evaluable by anyone. A consuming flake typically declares its own inputs as `follows = "othrys/<name>"` so hosts build against the exact versions this library is locked to (see [Host Configuration](./host-configuration.md)).
