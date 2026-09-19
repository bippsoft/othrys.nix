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

## Generation Limit

`maxGenerations` is how many of the newest generations the bootloader keeps on
the boot partition and lists in its menu. It defaults to 5. Older generations
stay in the system profile and only leave the boot menu. The option maps to
`boot.loader.limine.maxGenerations`, or to `configurationLimit` for
`systemd-boot` and GRUB. Lanzaboote takes its limit from the `systemd-boot`
option. `null` writes nothing and leaves the bootloader's own default, which is
no limit for Limine and `systemd-boot`.

The limit exists because every listed generation has its kernel and its initrd
copied to the boot partition. With no limit that is every generation in the
profile, so the partition fills. Limine removes unused files only at the end of
an install that succeeds. Once the partition is full, a switch fails with
`No space left on device` in the bootloader install, and no later switch can
free the space.

An install copies the new generation before it removes an old one, so the
partition has to hold the limit plus one. One generation costs its kernel plus
its initrd, and that varies a great deal between hosts.

| Cost of one generation | 1G partition holds | Highest safe `maxGenerations` |
|------------------------|--------------------|-------------------------------|
| 40M | 25 | 24 |
| 110M | 9 | 8 |
| 165M | 6 | 5 |
| 220M | 4 | 3 |

On a running Limine host, the size `sudo du -sh /boot/limine/kernels` reports,
divided by the number of kernel and initrd pairs in that directory, gives the
cost. A host with a large initrd, which a
GPU driver loaded in the initrd typically causes, sets a lower number than the
default.

### Recovering a full boot partition

The limit cannot help until one install succeeds, so a partition that is
already full needs space freed by hand. The installer names each file after the
store directory it came from, such as `<hash>-linux-6.18.51-bzImage`, which
makes the files of kept generations easy to tell apart.

1. Delete old generations from the profile, keeping the newest three:
   `sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +3`
1. List the boot files that no kept generation, nor the booted or the current
   system, points at:

   ```bash
   sudo bash -c '
   keep=$(for g in /nix/var/nix/profiles/system-*-link /run/booted-system /run/current-system; do
     for f in kernel initrd; do basename "$(dirname "$(readlink -f "$g/$f")")"; done
   done | sort -u)
   find /boot/limine -type f \( -name "*-bzImage" -o -name "*-initrd" -o -name "*.tmp" \) | while read -r p; do
     b=$(basename "$p"); hit=0
     for k in $keep; do case "$b" in "$k"-*) hit=1 ;; esac; done
     [ "$hit" = 0 ] && du -h "$p"
   done'
   ```

1. Read the list. Then run the same command with `du -h "$p"` replaced by
   `rm -v "$p"`.
1. Switch again. A successful install rewrites the boot menu from the kept
   generations.

Until that switch succeeds, the old boot menu still lists the deleted
generations, and those entries do not boot. The newest entries keep every file
they need.

## Secure Boot

When `othrys.system.bootloader.secureBoot = true`:

- `sbctl` is installed for managing Secure Boot keys
- Keys in `/var/lib/sbctl` are persisted across reboots (via impermanence)
- With `"limine"`, `boot.loader.limine.secureBoot.enable` is set and Limine signs itself with the sbctl keys
- With `"systemd-boot"`, `boot.lanzaboote` is enabled with `pkiBundle = "/var/lib/sbctl"`, and `boot.loader.systemd-boot.enable` goes to `false` because lanzaboote installs and signs systemd-boot itself

The [Secure Boot guide](../guides/secure-boot.md) walks through key creation and enrollment.

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
