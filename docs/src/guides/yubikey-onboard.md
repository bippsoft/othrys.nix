# YubiKey Onboarding

Interactive script for provisioning one or more YubiKeys with PGP keys, U2F credentials, and age identity for sops-nix. Supports both new key generation and key rotation from an existing backup. Follows [drduh's YubiKey Guide](https://github.com/drduh/YubiKey-Guide).

## Quick Start

```bash
# New key generation
just yubikey-onboard

# Key rotation from existing master key backup
just yubikey-onboard -- --from-backup /mnt/usb/yubikey-backup

# Health check on currently inserted YubiKey
just yubikey-onboard -- --verify
```

## Options

### Modes

| Flag | Description |
|------|-------------|
| *(default)* | Generate new PGP keys and provision YubiKey(s) |
| `--from-backup <path>` | Import an existing master key and provision YubiKey(s) (key rotation) |
| `--verify` | Check the currently inserted YubiKey's health and config |

### Key Identity

| Flag | Description |
|------|-------------|
| `--name <name>` | Real name for the PGP key |
| `--email <email>` | Email address for the PGP key |
| `--expiry <duration>` | Subkey expiry period (default: `2y`) |

Name and email have no defaults. Both are prompted for when the flag is absent,
and an empty answer is refused, since the pair becomes a permanent PGP identity.

### Provisioning

| Flag | Description |
|------|-------------|
| `--backup-dir <path>` | Master key backup directory (required, skips the prompt) |
| `--force-volatile` | Allow a backup directory the host may not persist |
| `--no-passphrase` | Leave the master key unprotected (escape hatch) |
| `--algo <algorithm>` | Force key algorithm: `ed25519` or `rsa4096` (auto-detected by default) |
| `--key-count <n>` | Number of YubiKeys to provision (skips the "provision another?" prompt) |
| `--dry-run` | Walk through all phases without destructive operations |

The backup directory has no default either. It used to offer
`/tmp/yubikey-backup-<date>`, which is predictable, unencrypted, and on most
hosts does not survive a reboot, so pressing Enter put the only copy of a master
key somewhere it could vanish. The script refuses a target that looks volatile,
by filesystem type or by path, and `--force-volatile` overrides that for an
operator who knows the location is kept.

### Examples

```bash
# Preview the full workflow without touching the YubiKey
just yubikey-onboard -- --dry-run

# Non-interactive new key generation for 2 YubiKeys
just yubikey-onboard -- --name "alice" --email "alice@example.com" \
  --expiry 2y --backup-dir /mnt/usb/backup --key-count 2

# Rotate onto a replacement YubiKey using existing master key
just yubikey-onboard -- --from-backup /mnt/usb/backup/master-secret.key

# Force RSA 4096 for an older YubiKey
just yubikey-onboard -- --algo rsa4096
```

## Nix Package

The script is packaged as a Nix derivation at `flake/packages.nix` and exposed as `packages.x86_64-linux.yubikey-onboard`. All runtime dependencies (gnupg, yubikey-manager, pam_u2f, age-plugin-yubikey, ssh-to-age, pinentry-curses, openssh) are pinned via the flake lockfile.

```bash
# Via justfile (recommended)
just yubikey-onboard

# Via nix run directly
nix run .#yubikey-onboard

# With arguments
nix run .#yubikey-onboard -- --verify
```

## Prerequisites

- A YubiKey 5 series (firmware 5.2.3+ for ed25519, older keys fall back to RSA 4096)
- Removable media for master key backup (new key mode) or the existing backup (rotation mode)

## Workflow

The script generates PGP keys once (or imports from backup), then provisions one or more YubiKeys with the same subkeys for redundancy. After the first YubiKey is provisioned, the script prompts to provision additional keys, restoring the subkeys from backup between each `keytocard` pass.

| Phase | Runs | Description |
|-------|------|-------------|
| 0 | Once | **Preflight**, verify tools, detect YubiKey firmware |
| 1 | Once | **PGP Key Generation** or **Import from Backup** |
| 2 | Once | **Master Key Backup** (skipped in `--from-backup` mode) |
| 3-6 | Per key | **Provision YubiKey**, reset, keytocard, PINs, U2F, age identity |
| 7 | Once | **SSH Keygrip**, extract authentication subkey keygrip |
| 8 | Once | **Public Key Import**, import into persistent keyring |
| 9 | Once | **Encrypted Backup**, age-encrypt the master key and remove the plaintext |
| 10 | Once | **Summary**, print all values for NixOS config |

## Phase Details

### Phase 0: Preflight Checks

Verifies required tools are available, detects the YubiKey (serial and firmware), and determines the key algorithm. The `--algo` flag overrides auto-detection.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:preflight}}
```

### Phase 1: PGP Key Generation

Generates a master key (Certify only) and three subkeys (Sign, Encrypt, Authenticate) in a temporary GNUPGHOME on ramfs, so the key never touches persistent storage or swap. See Security Notes for the fallback when unprivileged user namespaces are unavailable.

The temporary GPG environment uses a hardened `gpg.conf` matching the settings in `modules/services/security/yubikey.nix` and `pinentry-curses` for terminal PIN entry.

The `--name`, `--email`, and `--expiry` flags skip the interactive prompts. Name and email are refused if empty.

The phase ends by setting a passphrase on the master key, through gpg-agent's own pinentry on the same terminal. It will not advance to the backup phase while the key is unprotected unless `--no-passphrase` was given.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:keygen}}
```

### Phase 1 (alternate): Import from Backup

When `--from-backup` is used, the script imports an existing master key instead of generating a new one. It offers to generate fresh subkeys (recommended for rotation) or reuse the existing ones from the backup.

This mode is intended for:

- **Key rotation**. Expired subkeys, generate new ones from the same master
- **Replacement YubiKey**. Lost/damaged key, provision a new one with existing subkeys

```bash
{{#include ../../../scripts/yubikey-onboard.sh:from-backup}}
```

### Phase 2: Master Key Backup

Exports the master secret key, subkeys, public key, and revocation certificate to a user-specified directory (or the path from `--backup-dir`). Displays SHA256 checksums for verification. **The script will not proceed until backups are confirmed** -- this is a hard gate because `keytocard` in Phase 3 is irreversible.

This phase is skipped in `--from-backup` mode since the backup already exists.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:backup}}
```

### Phase 3: Move Subkeys to YubiKey

This phase uses a **guided manual approach** rather than full automation. The `gpg --edit-key ... keytocard` command requires interactive PIN entry and confirmation prompts that are fragile to automate across GPG versions.

The script prints exact step-by-step instructions, then verifies via `gpg --card-status` that all three key slots are populated.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:keytocard}}
```

### Per-YubiKey Provisioning (Phases 3-6)

For each YubiKey, the script runs:

- **Reset**. Optionally factory reset the OpenPGP and FIDO2 applets
- **Phase 3**: Guided `keytocard` to move subkeys to the YubiKey
- **Phase 4**: Change default PINs (user: `123456`, admin: `12345678`) via `ykman`
- **Phase 5**: Register a U2F credential with `pamu2fcfg -n -o pam://yubi`
- **Phase 6**: Generate an age identity with `age-plugin-yubikey --generate` (touch: always, PIN: once)

After the first YubiKey is provisioned, the script asks whether to provision another (or provisions exactly `--key-count` keys). It restores the subkeys from backup between each `keytocard` pass.

### Post-Provisioning (Phases 7-9)

- **Phase 7**: Extract the authentication subkey's keygrip for SSH and export the SSH public key (same for all keys since they share the same GPG key)
- **Phase 8**: Import the public key into the persistent `~/.gnupg` keyring and set ultimate trust

### Encrypted Master Key Backup

Runs after every YubiKey is provisioned, and the ordering is forced rather than
chosen. The plaintext backup has to exist before `keytocard` in Phase 3, since
that move is irreversible, and it has to survive the provisioning loop because
subkeys are re-imported from it between each key. The age recipients do not
exist until Phase 6 has run for a token. There is no earlier point at which both
are true.

Two files are written, because `age` refuses `-p` and `-r` together:

| File | Opens with |
|------|------------|
| `master-secret.key.age` | any provisioned YubiKey, or an extra `--age-recipient` |
| `master-secret.key.pass.age` | the passphrase entered during this phase |

The passphrase copy is not redundancy for its own sake. A master key backup
exists precisely to survive losing every token, so encrypting it *only* to those
tokens makes it worthless in the situation it was created for. `--no-age-passphrase`
declines it.

The plaintext is removed only after a copy has been decrypted and compared byte
for byte in the same run. An encrypted file that was written but never opened
does not license deleting the only copy of a master key, so a failed
verification keeps the plaintext and says so. `--keep-plaintext` retains it even
on success, and `--no-age-backup` skips the phase entirely.

Verifying the token copy needs the inserted YubiKey's PIN and a touch, and can
only test the token currently in the reader, which after a multi-key run is the
last one provisioned. The other tokens are the same mechanism and the same
ciphertext, but this phase has not proved them.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:age-backup}}
```

### Phase 9: Summary Output

Prints all values ready to paste into the NixOS host configurations:

- `sshKeygrips`, GPG keygrip for SSH authentication (shared across all keys)
- `u2fMappings`, one U2F credential per YubiKey
- `ageIdentityStubs`, age identity block for sops-nix (primary key)
- Git signing key fingerprint
- SSH public key for GitHub/servers
- age recipients for all provisioned keys (add all to `.sops.yaml` for redundancy)

A copy is saved beside the backup as `yubikey-onboard-summary-*.txt`, since it carries the keygrip, the age recipients and the U2F credential lines that the host configuration needs later.

## Verify Mode

The `--verify` flag runs a standalone health check on the currently inserted YubiKey:

- Detects the YubiKey (serial, firmware)
- Checks all three OpenPGP card slots (Signature, Encryption, Authentication)
- Checks FIDO2 applet accessibility
- Lists age identities in PIV slots
- Checks gpg-agent for SSH key availability
- Cross-references the YubiKey serial against the NixOS host configs

```bash
{{#include ../../../scripts/yubikey-onboard.sh:verify}}
```

## After Onboarding

1. Update your fleet's host configurations with the output values
1. Update `.sops.yaml` in the secrets repo with **all** age recipients
1. Re-encrypt secrets: `sops updatekeys <secret-files>`
1. Upload public key to GitHub: `gpg --armor --export <FINGERPRINT>`
1. Rebuild: `just switch <hostname>`

## Script Entrypoint

```bash
{{#include ../../../scripts/yubikey-onboard.sh:main}}
```

## Security Notes

- The script runs with `umask 077`, so every file it writes is owned by the
  caller and readable by nobody else
- The master key lives in a temporary GNUPGHOME on **ramfs** and is cleaned up on
  exit via an EXIT trap. ramfs pages are never written to disk or swap. The
  script re-execs itself under `unshare -Urm --propagation slave` to mount it,
  which needs no privilege, and the mount dies with the process rather than
  needing an unmount that could fail. Where unprivileged user namespaces are
  disabled it falls back to `/dev/shm` and says so. That fallback is tmpfs, whose
  pages are swappable, so on a host with active swap the key can reach disk while
  it exists, and the script warns when it sees swap
- The master key is generated unprotected and a passphrase is set before the
  backup phase. Entry runs through gpg-agent's own pinentry on the same terminal,
  so the passphrase stays in the agent's mlocked memory and never reaches a shell
  variable. A gate re-reads the on-disk protection state afterwards, so a
  cancelled dialog cannot pass. `--no-passphrase` is the explicit escape hatch
- The backup directory has no default and a volatile target is refused unless
  `--force-volatile` is given, since the backup is the only copy of a master key
  whose subkeys cannot be extracted from the YubiKey again
- Default YubiKey PINs should always be changed during Phase 4
- The GPG configuration follows [drduh's hardened settings](https://github.com/drduh/config/blob/master/gpg.conf)
- In `--from-backup` mode, the master key is loaded into the same ramfs GNUPGHOME
  from the backup, so it still never persists to disk
