# Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) using age encryption via YubiKey.

## Architecture

This repository holds no secrets. `othrys.system.secrets` provides the sops-nix
plumbing (age decryption, YubiKey identities), and the encrypted material lives
in the consuming flake, typically as a private `secrets` input that its hosts
declare and its CI stubs out.

- Encrypted with age, backed by a YubiKey identity
- Decrypted at activation time by sops-nix, never stored in the Nix store
- Modules take runtime file paths, so what provides them is the consumer's choice

## Options

```nix
{{#include ../../../modules/system/secrets.nix:secrets-options}}
```

## Host Configuration

Secrets are declared in host configs (not in modules) using `othrys.system.secrets` for infrastructure and `sops.secrets.*` for individual secret declarations. See [Host Configuration](../architecture/host-configuration.md) for a real example.

## Secret Files

| File | Purpose |
|------|---------|
| `common.yaml` | Secrets shared by every host (user passwords, service credentials) |
| `<hostname>.yaml` | Host-specific secrets (e.g. the boot recovery password) |

## YubiKey Setup

The `othrys.services.security.yubikey` module provides `age-plugin-yubikey` for manual sops editing. Touch policy is set to "Always", so a physical touch is required for every decryption.

To provision a new YubiKey with an age identity for sops-nix (along with PGP keys and U2F credentials):

```bash
# New key generation
just yubikey-onboard

# Rotate keys using existing master key backup
just yubikey-onboard -- --from-backup /mnt/usb/yubikey-backup
```

The script generates the `ageKeyFile` value and age recipient needed for the host configs and `.sops.yaml`. When provisioning multiple YubiKeys for redundancy, add all age recipients to `.sops.yaml`. See the [YubiKey Onboarding guide](../guides/yubikey-onboard.md) for the full workflow.

## Key Rotation

A YubiKey backs four independent credential surfaces. Rotation means updating each one it touches. **Redundancy is the backup strategy**: enroll several YubiKeys so losing one is a revocation, not a lockout. The boot passphrase (sops `security/boot/password`) is the break-glass slot.

| Surface | Where it's declared | Rotated with |
|---------|--------------------|--------------|
| **age / sops** identity | `othrys.system.secrets.ageKeyFile` (host) + recipients in `.sops.yaml` (secrets repo) | `sops updatekeys` |
| **LUKS** root unlock | `othrys.system.disko.luks.fido2.enable` (FIDO2 keyslot on the device) | `just luks-enroll` / `systemd-cryptenroll --wipe-slot` |
| **SSH** (GPG auth) | `othrys.services.security.yubikey.sshKeygrips` (host) | edit list + rebuild |
| **U2F** login/sudo | `othrys.services.security.yubikey.u2fMappings.<user>` (host) | edit list + rebuild |

> The secret files and `.sops.yaml` live in the private `secrets` flake input, so rotation spans **two repos**: this config (host options) and the secrets repo (`.sops.yaml` + `sops updatekeys`).

### Add a YubiKey (grow redundancy)

1. Provision the key: `just yubikey-onboard` (or `just yubikey-onboard -- --from-backup <path>` to clone an existing identity from its master-key backup). Note the printed age recipient, keygrip, and U2F line.
1. **age**: add the new recipient to `.sops.yaml` in the secrets repo, then re-encrypt every secret so the new key can read it:
   ```bash
   sops updatekeys secrets/*.yaml
   ```
1. **LUKS**: with the root unlocked, add a FIDO2 keyslot for the new key (repeat per host):
   ```bash
   just luks-enroll            # touch the key when it blinks, break-glass passphrase authorizes the new slot
   sudo systemd-cryptenroll /dev/disk/by-id/<root>   # verify the token count
   ```
1. **SSH / U2F**: append the new keygrip to `sshKeygrips` and the new credential to `u2fMappings.<user>` in the host config.
1. `just switch <host>` to apply, then confirm login/sudo/SSH work with the new key **before** relying on it.

### Revoke a YubiKey (lost or compromised)

Do this from a machine that still has a working key. Order matters. Re-encrypting **before** removing the compromised recipient's access is impossible, so revoke everywhere:

1. **age**: remove the lost key's recipient from `.sops.yaml`, then `sops updatekeys` all secret files. The old key can no longer decrypt them.
1. **LUKS**: wipe its keyslot on every host (list first to find the slot):
   ```bash
   backing=$(sudo cryptsetup status cryptroot | awk '/device:/ {print $2}')
   sudo systemd-cryptenroll "$backing"                 # identify the FIDO2 slot
   sudo systemd-cryptenroll --wipe-slot=<n> "$backing" # or --wipe-slot=fido2 to drop all FIDO2 slots and re-enroll survivors
   ```
1. **Config**: delete the key's `sshKeygrips` entry, its `u2fMappings.<user>` credential, and its `ageKeyFile` block if it was the manual-edit identity. Ensure at least one surviving key remains in each list (the `u2fMappings` assertion blocks a login lockout).
1. **Rotate exposed secrets**: anything the lost key could decrypt is potentially compromised. Regenerate user/boot passwords and any service credentials, re-encrypt, and `just switch` every host.
1. Confirm the revoked key is rejected (SSH, sudo, and, after a reboot, LUKS unlock).
