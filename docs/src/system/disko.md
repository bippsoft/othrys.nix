# Disko (Disk Partitioning)

Declarative disk configuration with LUKS encryption and BTRFS subvolumes.

## Importing

The layout is the separate export `nixosModules.disko`, which
`nixosModules.default` does not import. It is the only othrys module that writes
into the `disko` option namespace, so a host that wants it imports the export
together with the disko module, and a host that partitions another way imports
neither:

```nix
# flake inputs
disko.follows = "othrys/disko";

# host modules
inputs.othrys.nixosModules.disko
inputs.disko.nixosModules.disko
```

The export without the disko module fails at evaluation, since a write into an
undeclared option namespace fails whatever guards it.

## Layout

- **EFI boot partition**. Unencrypted FAT32
- **Swap partition**. LUKS encrypted, or encrypted with a random key on each boot when `swap.randomEncryption` is on, which is the default with `luks.fido2.enable`
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
};
```

`luks.passwordFile` stays at its default of `null` for an install, and disko
then prompts for the LUKS passphrase when it formats the disk. A sops secret
does not exist on the target at that point, so a secrets path there names a
file the installer cannot read. The option is for a host where the file is
already present at format time.

`device` is meant to be a path under `/dev/disk/by-id/`. A name such as
`/dev/sda` evaluates with a warning, since the kernel assigns those in probe
order and disko formats whatever disk carries the name.

Both LUKS volumes are formatted with stated parameters, which are LUKS2,
`aes-xts-plain64` with a 512-bit key, SHA-256 and Argon2id. They match the
current cryptsetup defaults and apply at format time only.

With the layout on, `othrys.system.impermanence.device` defaults to the LUKS
mapping of the root, `/dev/mapper/<luks.name>`, which is the device the boot wipe
mounts. See [Impermanence](impermanence.md).

`luks.allowDiscards` passes TRIM through the encryption layer, and
`services.fstrim.enable` follows it at `mkDefault`, so the weekly timer is what
issues the discards.

The initial install runs disko once in `destroy,format,mount` mode against the
host, which erases the target disk. This repository ships no recipe for that
step, since it holds no hosts. The [Installation](../guides/installation.md)
guide walks through it with the consuming fleet's justfile.

