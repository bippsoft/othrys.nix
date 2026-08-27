# othrys.nix

A reusable NixOS module library of composable, opt-in modules under a unified `othrys.*` namespace, spanning workstation, server, router and security. It is consumed as a flake input by a private fleet repository that holds the actual host configurations.

## Design Principles

- **Library, not config.** This repository exports modules. Hosts, secrets and identity live in the consuming flake.
- **Capabilities curated, opinions configurable.** Modules define what can be done, such as window focus, an nftables router ruleset or alias groups. Options decide the keys, interfaces, apps and workflow.
- **Identity-free.** No usernames, domains, keys or hardware IDs are baked in. Everything personal arrives through options with neutral defaults.
- **Flakes** with flake-parts for modular, reproducible structure.
- **Impermanence.** An ephemeral root filesystem with opt-in persistence.
- **One namespace.** Every custom option lives under `othrys.*`.
- **Home Manager** integrated as a NixOS module rather than standalone.
- **Stylix** for system-wide base16 theming from a single color scheme.

## How This Book Is Organized

- **Architecture.** How the flake and modules fit together, and the contract a consuming flake must satisfy.
- **System Infrastructure.** Disk partitioning, impermanence, bootloader, secrets.
- **Module Reference.** One page per module category with options and code snippets.
- **Guides.** Step-by-step walkthroughs for common tasks.
- **Development.** Dev shells, CI, linting.
- **Reference.** Justfile commands, all module options, keybindings.
