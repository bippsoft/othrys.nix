# Flake Inputs

All external dependencies are declared in `flake.nix`:

```nix
{{#include ../../../flake.nix:inputs}}
```

## Input Summary

| Input | Purpose |
|-------|---------|
| `ashell` | GPU-accelerated Wayland status bar, the default of `othrys.desktop.ashell.package` |
| `nixpkgs` | Main package set (unstable channel) |
| `flake-parts` | Modular flake framework |
| `home-manager` | Declarative user environment management, written into by the optional `nixosModules.home` export |
| `hyprland` | Wayland compositor (pinned, not following nixpkgs), the default of `othrys.desktop.compositors.hyprland.package` and `portalPackage` |
| `niri` | niri-flake, the typed `programs.niri.settings` module the Niri compositor module imports |
| `disko` | Declarative disk partitioning, written into by the optional `nixosModules.disko` export |
| `nix-index-database` | Prebuilt database for `comma` and `nix-locate`, as the Home Manager module `othrys.apps.comma` imports |
| `impermanence` | Opt-in state persistence, written into by the optional `nixosModules.impermanence` export |
| `nixvim` | Neovim configuration via Nix modules, as the Home Manager module `othrys.apps.nixvim` imports |
| `stylix` | System-wide theming, read by the optional Stylix adapter and the checks |
| `git-hooks` | Pre-commit hooks (treefmt, Statix, Deadnix, commitizen, gitleaks and the three repository hooks) |
| `treefmt-nix` | Multi-language formatter behind `nix fmt` |
| `sops-nix` | Secrets management with age encryption, written into by the optional `nixosModules.secrets` export |
| `lanzaboote` | Secure Boot for systemd-boot (read by the checks only, since no module imports it and a consumer who wants it declares their own) |

The private `secrets` input is declared only in the consuming fleet flake, never here, since this flake must remain evaluable by anyone.

## What a Consumer Declares

A consuming flake declares `othrys`, `nixpkgs` and the inputs whose modules it imports itself. `home-manager`, `impermanence`, `disko`, `sops-nix` and `stylix` are for a host that imports the matching othrys export, and none of them is required. Each is typically written as `follows = "othrys/<name>"`, so hosts build against the exact versions this library is locked to (see [Host Configuration](./host-configuration.md)). A flake whose hosts import `nixosModules.full` declares none of the five, since that export imports each upstream module from this flake's lock.

It declares none of `ashell`, `hyprland`, `nixvim`, `nix-index-database` or `niri`. `flake/modules.nix` hands the first four to the modules from this flake's lock, as a module argument named `othrysInputs`, and imports niri-flake's module directly. An input of one of those names in the consuming flake is not read by any module.

A consumer changes what a module builds from in one of two ways.

- **A `package` option.** `othrys.desktop.compositors.hyprland.package` and `portalPackage`, and `othrys.desktop.ashell.package`, take any package. The defaults are the packages of the locked flakes.
- **A `follows` on this flake's input.** `inputs.othrys.inputs.<name>.follows = "<name>"` replaces the locked flake with the consumer's own. It is the only way to change nixvim and nix-index-database, which are Home Manager modules with no package to set.

```nix
inputs = {
  othrys.url = "github:<owner>/othrys.nix";

  # The consumer's own nixvim, in place of the one othrys locks.
  nixvim.url = "github:nix-community/nixvim";
  othrys.inputs.nixvim.follows = "nixvim";
};
```

The Hyprland input deliberately does not follow nixpkgs, so its packages match what hyprland.cachix.org serves. A `follows` that replaces it, or a `package` from another source, gives up those cache hits.
