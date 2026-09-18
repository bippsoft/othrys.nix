# Bootloader & Secure Boot

Supports Limine (default), systemd-boot, and GRUB. Secure Boot via sbctl, natively on Limine and through lanzaboote on systemd-boot.

## Configuration

```nix
{{#include ../../../modules/system/bootloader.nix:bootloader-config}}
```

## Bootloader Selection

Set in host config via `othrys.system.bootloader.type`:

| Value | Bootloader | Secure Boot | Notes |
|-------|-----------|-------------|-------|
| `"limine"` | Limine | Yes, native | Default. Supports extra entries (dual-boot). |
| `"systemd-boot"` | systemd-boot | Yes, needs lanzaboote | Simple, well-supported. |
| `"grub"` | GRUB | Rejected | EFI support, `device = "nodev"`. |
| `"none"` | None | Rejected | The module manages no bootloader and the host configures one itself. |

## Secure Boot

When `othrys.system.bootloader.secureBoot = true`:

- `sbctl` is installed for managing Secure Boot keys
- Keys in `/var/lib/sbctl` are persisted across reboots (via impermanence)
- With `"limine"`, `boot.loader.limine.secureBoot.enable` is set and Limine signs itself with the sbctl keys
- With `"systemd-boot"`, `boot.lanzaboote` is enabled with `pkiBundle = "/var/lib/sbctl"`, and `boot.loader.systemd-boot.enable` goes to `false` because lanzaboote installs and signs systemd-boot itself

### systemd-boot needs lanzaboote

`nixosModules.default` does not import lanzaboote, so a host that never enables Secure Boot on systemd-boot needs no extra input. A host that does adds the input and the module in the consuming flake:

```nix
inputs.lanzaboote.url = "github:nix-community/lanzaboote/<release-tag>";
```

```nix
modules = [inputs.lanzaboote.nixosModules.lanzaboote];
```

Without that import, `secureBoot = true` on `"systemd-boot"` fails evaluation with an assertion that names both lines.

### What is rejected

- GRUB has no Secure Boot support in NixOS, so `secureBoot = true` with `type = "grub"` fails evaluation instead of silently doing nothing.
- `type = "none"` fails the same way, since the module manages no bootloader there.

### Limits

- No option exists for TPM measured boot. Lanzaboote's `boot.lanzaboote.measuredBoot` options are left for the host to set directly.
- The `eval-bootloader` check evaluates every type with `secureBoot` off and on, and reads back the loader options each combination sets. No check boots a VM under firmware Secure Boot, so the checks prove evaluation only.

## Dual Boot

Add extra entries via `othrys.system.bootloader.extraEntries` (Limine format):

```nix
othrys.system.bootloader.extraEntries = ''
  /Windows 11
      protocol: efi
      path: uuid(...):/.../bootmgfw.efi
'';
```
