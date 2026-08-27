# Overview

othrys.nix is a public NixOS module library built with [flake-parts](https://flake.parts/). It exports reusable modules under the `othrys.*` namespace; host configurations live in a separate private fleet flake that consumes this one as an input (see [Host Configuration](./host-configuration.md)).

## Repository Structure

```
flake.nix                    # Flake entrypoint (no hosts, no secrets)
flake/               # Flake-parts modules
  ├── modules.nix            # Exported nixosModules (incl. aggregate `default`)
  ├── packages.nix           # Packaged scripts and tools
  ├── dev-shells.nix         # Development environments
  ├── treefmt.nix            # Multi-language formatter (nix fmt)
  └── checks.nix             # CI checks (pre-commit, impermanence VM test)
modules/                     # Reusable NixOS modules (othrys.* namespace)
  ├── system/                # System fundamentals
  │   ├── locale.nix         # Locale, timezone, console
  │   ├── users.nix          # User accounts, passwords, essential packages
  │   ├── nix.nix            # Nix daemon, flakes, caches, GC
  │   ├── kernel.nix         # Kernel selection
  │   ├── bootloader.nix     # Bootloader + Secure Boot
  │   ├── disko.nix          # Declarative disk partitioning
  │   ├── impermanence.nix   # Ephemeral root wipe
  │   ├── persistence.nix    # System-critical persistence
  │   ├── secrets.nix        # sops-nix secrets
  │   ├── git.nix            # Git configuration
  │   ├── stylix.nix         # System-wide theming
  │   └── shell/             # Shell (Zsh, Bash, Starship)
  ├── desktop/               # Desktop environment
  │   ├── compositors/       # Hyprland
  │   ├── login.nix          # greetd login manager
  │   └── uwsm.nix           # Session management
  ├── hardware/              # Hardware
  │   ├── audio.nix          # PipeWire audio
  │   ├── webcam.nix         # Webcam support
  │   ├── graphics/          # GPU drivers (NVIDIA, PRIME offload)
  │   ├── laptop/            # Laptop features + specific models
  │   └── wireless/          # Bluetooth, WiFi
  ├── services/              # Services
  │   ├── security/          # Sudo, Polkit, YubiKey, fail2ban
  │   ├── containerization/  # Podman, Docker, k3s
  │   ├── mounts/            # Disk and CIFS mounts
  │   └── *.nix              # SSH, Tailscale, firewall, monitoring, etc.
  └── apps/                  # Applications
      ├── cli/               # nixvim, ai (claude-code, mcp), gh, yazi, ...
      └── gui/               # floorp, ghostty, gaming/, vscode, ...
assets/                      # Themes (base16 YAML)
scripts/                     # Operational scripts
  └── yubikey-onboard.sh     # YubiKey provisioning (PGP, U2F, age)
docs/                        # This book
```

The consuming fleet flake holds everything machine- or person-specific: host configurations, shared profiles, fleet data (SSH host maps, cache keys, YubiKey identities), and the private secrets input.

## Flake Inputs

```nix
{{#include ../../../flake.nix:inputs}}
```

## Flake Imports

```nix
{{#include ../../../flake.nix:imports}}
```
