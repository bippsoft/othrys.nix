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

`device` is meant to be a path under `/dev/disk/by-id/`. A name such as
`/dev/sda` evaluates with a warning, since the kernel assigns those in probe
order and disko formats whatever disk carries the name.

Both LUKS volumes are formatted with stated parameters, which are LUKS2,
`aes-xts-plain64` with a 512-bit key, SHA-256 and Argon2id. They match the
current cryptsetup defaults and apply at format time only.

`luks.allowDiscards` passes TRIM through the encryption layer, and
`services.fstrim.enable` follows it at `mkDefault`, so the weekly timer is what
issues the discards.

Initial install: `just disk <hostname>`
