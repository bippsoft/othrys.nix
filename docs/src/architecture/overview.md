# Overview

othrys.nix is a public NixOS module library built with [flake-parts](https://flake.parts/). It exports reusable modules under the `othrys.*` namespace; host configurations live in a separate private fleet flake that consumes this one as an input (see [Host Configuration](./host-configuration.md)).

## Repository Structure

```
flake.nix                    # Flake entrypoint (no hosts, no secrets)
flake/                       # Flake-parts modules
  ├── modules.nix            # Exported nixosModules (incl. aggregate `default`)
  ├── templates.nix          # `nix flake init` starting points
  ├── packages.nix           # Packaged scripts and tools
  ├── dev-shells.nix         # Development environments
  ├── treefmt.nix            # Multi-language formatter (nix fmt)
  ├── docs-options.nix       # Generated othrys.* options reference
  └── checks/                # Flake checks, with each VM test and read-back in its own file
modules/                     # Reusable NixOS modules (othrys.* namespace)
  ├── system/                # System fundamentals
  │   ├── user.nix           # Primary user identity option
  │   ├── users.nix          # User account, shell, the Home Manager registry
  │   ├── locale.nix         # Locale, timezone, console
  │   ├── nix.nix            # Nix daemon, substituters, GC
  │   ├── kernel.nix         # Kernel selection
  │   ├── hardening.nix      # Opt-in kernel and sysctl hardening
  │   ├── networking.nix     # systemd-networkd interfaces, bridges, VLANs
  │   ├── auto-upgrade.nix   # Unattended upgrades with signature verification
  │   ├── bootloader.nix     # Bootloader + Secure Boot
  │   ├── disko.nix          # Declarative disk partitioning
  │   ├── impermanence.nix   # Ephemeral root wipe
  │   ├── persistence.nix    # System-critical persistence
  │   ├── secrets.nix        # sops-nix secrets
  │   ├── git.nix            # Git configuration
  │   └── shell/             # Shell (Zsh, Bash, Starship)
  ├── theme/                 # The theme every module reads
  │   ├── default.nix        # othrys.theme: palette, fonts, opacity, wallpaper
  │   ├── schemes/           # Colour schemes as Nix data
  │   └── stylix.nix         # Stylix adapter, exported on its own
  ├── desktop/               # Desktop environment
  │   ├── compositors/       # Hyprland, Niri
  │   ├── ashell/            # Status bar
  │   ├── login.nix          # greetd login manager
  │   ├── idle.nix           # Staged idle policy
  │   ├── keyring.nix        # Secret Service provider
  │   ├── night-light.nix    # Color temperature shifting
  │   └── uwsm.nix           # Session management
  ├── hardware/              # Hardware
  │   ├── audio.nix          # PipeWire audio
  │   ├── webcam.nix         # Webcam support
  │   ├── scanner.nix        # SANE scanning
  │   ├── smart.nix          # Disk health monitoring
  │   ├── ups.nix            # UPS monitoring (NUT)
  │   ├── usb.nix            # USB utilities
  │   ├── graphics/          # NVIDIA, PRIME offload, shader cache
  │   ├── laptop/            # Laptop features + specific models
  │   └── wireless/          # Bluetooth, WiFi
  ├── services/              # Services
  │   ├── security/          # Sudo, Polkit, YubiKey, fail2ban, CrowdSec
  │   ├── containerization/  # Podman, Docker, k3s
  │   ├── mounts/            # Disk and CIFS mounts
  │   └── *.nix              # SSH, Tailscale, router, Traefik, monitoring, etc.
  ├── apps/                  # Applications
  │   ├── cli/               # nixvim, ai (claude-code, ollama, mcp), gh, yazi, ...
  │   ├── gui/               # floorp, ghostty, gaming/, vscode, ...
  │   └── languages/         # Per-language toolchains shared by both editors
  └── lib/                   # Shared option types, address helpers, the systemd sandbox baseline
templates/                   # The `nix flake init` template
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
