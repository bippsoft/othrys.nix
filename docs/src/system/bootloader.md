# Bootloader & Secure Boot

Supports Limine (default), systemd-boot, and GRUB. Secure Boot via sbctl.

## Configuration

```nix
{{#include ../../../modules/system/bootloader.nix:bootloader-config}}
```

## Bootloader Selection

Set in host config via `othrys.system.bootloader.type`:

| Value | Bootloader | Notes |
|-------|-----------|-------|
| `"limine"` | Limine | Default. Supports Secure Boot and extra entries (dual-boot). |
| `"systemd-boot"` | systemd-boot | Simple, well-supported. |
| `"grub"` | GRUB | EFI support, `device = "nodev"`. |

## Secure Boot

When `othrys.system.bootloader.secureBoot = true`:

- `sbctl` is installed for managing Secure Boot keys
- Keys are persisted across reboots (via impermanence)

## Dual Boot

Add extra entries via `othrys.system.bootloader.extraEntries` (Limine format):

```nix
othrys.system.bootloader.extraEntries = ''
  /Windows 11
      protocol: efi
      path: uuid(...):/.../bootmgfw.efi
'';
```
