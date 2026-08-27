# System

Core system modules under `othrys.system.*`, located in `modules/system/`. Each
is toggled by its own `enable` option (except `user`, which only declares the
identity option) and configures a fundamental part of the machine.

The disk, impermanence, bootloader, and secrets modules have dedicated pages
under **System Infrastructure**, and the rest are summarized here.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| User identity | `othrys.system.user.name` | Primary user account name, **required**, replaces the legacy `username` specialArg |
| Users | `othrys.system.users` | User account creation, shell, password wiring |
| Locale | `othrys.system.locale` | Timezone, locale, console font/keymap (defaults are identity-neutral: `UTC`) |
| Auto-upgrade | `othrys.system.autoUpgrade` | Unattended nixos-rebuild from the fleet flake |
| Nix | `othrys.system.nix` | Nix settings, GC/`nh`, substituters, optional Cachix |
| Kernel | `othrys.system.kernel` | Kernel package selection (disabled → NixOS default kernel) |
| Networking | `othrys.system.networking` | systemd-networkd: per-interface DHCP/static + bridges/VLANs (router topology) |
| Git | `othrys.system.git` | Git identity and aliases (home-manager) |
| Persistence | `othrys.system.persistence` | System/user state declarations for impermanence |
| Stylix | `othrys.system.stylix` | System-wide base16 theming (fonts/cursor/opacity) |
| Shell | `othrys.system.shell.{bash,zsh,starship}` | Interactive shells and prompt |

## Notes

- **User identity**: modules read `config.othrys.system.user.name`. It is a
  required option with no default and no `username` specialArg fallback, so set it
  per host. See the consumer contract in the repository `CLAUDE.md`.
- **Identity-neutral defaults**: `locale.timezone` defaults to `UTC` and
  `nix.nh.flake` defaults to `null`; set them per host. These are examples of
  the library's "sane, non-personal defaults" policy.

## Auto-upgrade

Unattended `nixos-rebuild` from the fleet flake on a schedule (daily 04:00
by default, randomized delay so a fleet doesn't stampede the repo host).
Reboots are opt-in and window-confined, and failures push through
`othrys-notify` when the notify module is enabled.

### Options

```nix
{{#include ../../../modules/system/auto-upgrade.nix:auto-upgrade-options}}
```
