# Installation

Fresh install from NixOS installation media, using this library's disko and impermanence modules from your own fleet flake. Commands below use the fleet justfile described in the [Justfile reference](../reference/justfile.md). Substitute your host names throughout.

## Prerequisites

- NixOS installation media (Ventoy recommended)
- A fleet flake consuming othrys.nix, with a host defined (see [Host Configuration](../architecture/host-configuration.md))
- Target disk identifier (`ls -l /dev/disk/by-id/`)
- YubiKey (for secrets management, post-install)

## Steps

### 1. Boot Installer and Clone

```bash
git clone <your-fleet-repo-url>
cd <your-fleet-repo>
```

### 2. Partition and Format

```bash
# WARNING: This erases the target disk!
just disk <hostname>
```

This runs disko in destroy/format/mount mode using the host's disk configuration.
You'll be prompted to set the **LUKS recovery passphrase** interactively (sops
secrets don't exist yet at this stage). Keep it safe, since it's the break-glass
fallback if your YubiKeys are ever unavailable.

### 3. Install NixOS

```bash
just install <hostname>
```

### 4. Reboot

```bash
reboot
```

### 5. Post-Install

After first boot (unlock with the recovery passphrase from step 2):

- Verify system with `just build <hostname>`
- Set up YubiKey: `just yubikey-onboard` (see [YubiKey Onboarding](./yubikey-onboard.md))
- Enroll each YubiKey for disk unlock: `just luks-enroll` (run once per key, since the
  extra keys are your backup). Afterwards, boot unlocks via YubiKey touch + PIN,
  with the recovery passphrase as fallback.
- Apply permanent config: `just switch <hostname>`

## Host Disk Configuration

Each host's disk is configured in your fleet's `hosts/<hostname>/default.nix` via `othrys.system.disko`. Update the `device` path to match your hardware. YubiKey unlock is toggled with `luks.fido2.enable` (which also switches swap to ephemeral random-key encryption, so hibernation is disabled).
