# Secure Boot

Enrolling your own Secure Boot keys on a host that uses `othrys.system.bootloader`. The keys are created with `sbctl`, the boot chain is signed on the next rebuild, and the firmware is given the keys last. That order matters, since a firmware that enforces Secure Boot before the boot chain is signed refuses to start it.

Two bootloader types support this. Limine signs itself natively, while systemd-boot is signed through lanzaboote. The steps are the same on both paths and the differences are called out where they occur. See [Bootloader & Secure Boot](../system/bootloader.md) for what the module sets on each.

## Prerequisites

- A UEFI host with `othrys.system.bootloader.enable = true` and `type` set to `"limine"` or `"systemd-boot"`. `"grub"` and `"none"` fail evaluation with `secureBoot = true`.
- On `"systemd-boot"`, a `lanzaboote` input in the consuming flake and `inputs.lanzaboote.nixosModules.lanzaboote` in the host's modules
- Access to the firmware setup screen
- Secure Boot switched off in the firmware for now, so that the still unsigned system keeps booting

## Steps

### 1. Create the Keys

`sbctl` is installed by the module once `secureBoot` is on, so the first run comes from nixpkgs.

```bash
sudo nix run nixpkgs#sbctl -- create-keys
```

The keys land in `/var/lib/sbctl`, readable by root only. They have to exist before the rebuild in step 2, because both installers sign during that rebuild. The Limine installer stops with `There are no sbctl secure boot keys present` when the directory is missing, and lanzaboote fails when it cannot read its key files.

On a host with `othrys.system.impermanence.enable = true`, copy the keys to the persistent volume before rebuilding. The module persists `/var/lib/sbctl` once `secureBoot` is on, and impermanence then bind-mounts the persisted directory over the original without copying what was there. Keys that exist only on the ephemeral root are hidden by that mount and gone after the next reboot.

```bash
sudo mkdir -p /persist/var/lib
sudo cp -a /var/lib/sbctl /persist/var/lib/
```

Replace `/persist` with the value of `othrys.system.impermanence.persistRoot` when the host changes it.

### 2. Rebuild with secureBoot

On Limine:

```nix
othrys.system.bootloader = {
  enable = true;
  secureBoot = true;
};
```

On systemd-boot:

```nix
othrys.system.bootloader = {
  enable = true;
  type = "systemd-boot";
  secureBoot = true;
};
```

Then rebuild.

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

On Limine the installer signs the Limine EFI binary with the `sbctl` keys. NixOS also turns on `enrollConfig`, `validateChecksums` and `panicOnChecksumMismatch` and refuses to evaluate without them, so Limine carries a hash of its own configuration, the configuration carries a checksum for every kernel and initrd, and a mismatch stops the boot.

On systemd-boot the module enables `boot.lanzaboote` with `pkiBundle = "/var/lib/sbctl"` and turns `boot.loader.systemd-boot.enable` off. Lanzaboote installs systemd-boot itself and writes one signed image for each generation, which vouches for the kernel and initrd stored beside it.

The nixpkgs documentation for `boot.loader.limine.secureBoot.enable` lists key enrollment before this rebuild. Signing needs only the keys on disk, so the order here works on Limine too, and it keeps the firmware from enforcing anything before a signed bootloader is in place.

### 3. Verify the Signatures

```bash
sudo sbctl verify
```

On Limine the file to look for is `EFI/limine/BOOTX64.EFI` under the EFI system partition, and it must be reported as signed. Kernel images are reported as not signed, which is expected because Limine checks them against the checksums in its configuration.

On systemd-boot `EFI/BOOT/BOOTX64.EFI`, `EFI/systemd/systemd-bootx64.efi` and every `EFI/Linux/nixos-generation-*.efi` must be signed. Kernel files under `EFI/nixos` are often reported as not signed, which the lanzaboote documentation lists as expected.

Do not continue while a file that must be signed is not.

### 4. Put the Firmware in Setup Mode

The firmware accepts new keys only in setup mode, and how to reach it differs between vendors.

```bash
systemctl reboot --firmware-setup
```

In the Secure Boot section, choose the entry that resets to setup mode. Where no such entry exists, erasing the Platform Key has the same effect. Where the firmware offers a separate entry that clears every key, leave it alone, since it also empties the forbidden signature database. Save, boot back into NixOS and confirm.

```bash
sudo sbctl status
```

`Setup Mode` must read `Enabled`.

### 5. Enroll the Keys

```bash
sudo sbctl enroll-keys --microsoft
```

`--microsoft` enrolls Microsoft's certificates next to your own, and it is usually kept. The option ROMs on graphics cards, network cards and storage controllers are typically signed by Microsoft, and a firmware that enforces Secure Boot refuses to run the ones it cannot verify. On some machines that leaves no video output, and with it no way to reach the firmware setup. A Windows installation on the same machine needs those certificates as well. Leave the flag out only on hardware known to carry no such option ROMs.

Some firmware also needs `--firmware-builtin`, which keeps the vendor's own keys so that firmware updates from the vendor still verify. The nixpkgs Limine documentation enrolls with both flags.

### 6. Reboot and Confirm

```bash
reboot
```

Some firmware switches Secure Boot on as soon as a Platform Key is enrolled. On the rest, enter the firmware setup once more and enable it. Then check the result from the running system.

```bash
bootctl status
```

The `System` block must show `Secure Boot: enabled (user)`. `bootctl` reads the firmware variables and reports the same line on Limine and on systemd-boot.

## After Enrollment

Every later rebuild signs what it installs, so nothing here has to be repeated. The private keys stay in `/var/lib/sbctl`, which the module persists when impermanence is on. Losing that directory means starting again from step 1, including another pass through setup mode.

## Limits

- No option exists for TPM measured boot, so nothing here ties disk unlock to the Secure Boot state.
- The `eval-bootloader` check proves that both paths evaluate. No check boots a VM under firmware Secure Boot, so the first boot after step 6 is the test.
