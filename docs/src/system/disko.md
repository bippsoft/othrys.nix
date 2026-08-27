# Disko (Disk Partitioning)

Declarative disk configuration with LUKS encryption and BTRFS subvolumes.

## Layout

- **EFI boot partition**. Unencrypted FAT32
- **Swap partition**. LUKS encrypted
- **Root partition**. LUKS encrypted BTRFS with subvolumes:
  - `root` → `/` (ephemeral, wiped on boot)
  - `persist` → `/persist` (all persistent state)
  - `nix` → `/nix` (Nix store)

## Options

```nix
{{#include ../../../modules/system/disko.nix:disko-options}}
```

## Partition Layout

```nix
{{#include ../../../modules/system/disko.nix:disko-partitions}}
```

## BTRFS Subvolumes

```nix
{{#include ../../../modules/system/disko.nix:disko-subvolumes}}
```

## Usage

Configure in host config:

```nix
othrys.system.disko = {
  enable = true;
  device = "/dev/disk/by-id/...";
  swapSize = "8G";
  luks.passwordFile = config.sops.secrets."security/boot/password".path;
};
```

Initial install: `just disk <hostname>`
