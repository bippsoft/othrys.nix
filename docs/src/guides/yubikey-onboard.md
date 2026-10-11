# YubiKey Onboarding

Interactive script for provisioning one or more YubiKeys with PGP keys, U2F credentials, and age identity for sops-nix. Supports both new key generation and key rotation from an existing backup. Follows [drduh's YubiKey Guide](https://github.com/drduh/YubiKey-Guide).

## Quick Start

```bash
# New key generation
just yubikey-onboard

# Key rotation from the backup directory a previous run left
just yubikey-onboard -- --from-backup /mnt/usb/yubikey-backup

# Health check on currently inserted YubiKey
just yubikey-onboard -- --verify
```

## Options

### Modes

| Flag | Description |
|------|-------------|
| *(default)* | Generate new PGP keys and provision YubiKey(s) |
| `--from-backup <path>` | Import an existing master key and provision YubiKey(s) (key rotation). The path is a backup directory, `master-secret.key.age`, `master-secret.key.pass.age` or a plaintext `master-secret.key` |
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
| `--allow-default-pins` | Finish even when a PIN, PUK or management key was not changed in this run |
| `--age-identity <file>` | age identity file that opens `master-secret.key.age` for `--from-backup` (default: the YubiKey in the reader) |
| `--dry-run` | Walk through all phases. Touches no YubiKey and no keyring, and writes no file |

The backup directory has no default either. It used to offer
`/tmp/yubikey-backup-<date>`, which is predictable, unencrypted, and on most
hosts does not survive a reboot, so pressing Enter put the only copy of a master
key somewhere it could vanish. The script refuses a target that looks volatile,
by filesystem type or by path, and `--force-volatile` overrides that for an
operator who knows the location is kept.

A dry run reads no token, so the serial it prints is the word `dry-run` and the
firmware is assumed to be current. It prints the directory a real run would save
its summary under and creates nothing there.

### Encrypted Backup

| Flag | Description |
|------|-------------|
| `--age-recipient <r>` | Extra age recipient for the token copies, repeatable |
| `--no-age-passphrase` | Skip the passphrase-encrypted copies |
| `--keep-plaintext` | Keep the plaintext exports after the encrypted copies verify |
| `--no-age-backup` | Do not produce encrypted copies at all |

### Examples

```bash
# Preview the full workflow without touching the YubiKey
just yubikey-onboard -- --dry-run

# Non-interactive new key generation for 2 YubiKeys
just yubikey-onboard -- --name "alice" --email "alice@example.com" \
  --expiry 2y --backup-dir /mnt/usb/backup --key-count 2

# Rotate from the passphrase copy, which needs no token to open
just yubikey-onboard -- --from-backup /mnt/usb/backup/master-secret.key.pass.age

# Rotate from the token copy, opened by a YubiKey provisioned earlier
just yubikey-onboard -- --from-backup /mnt/usb/backup/master-secret.key.age

# The same, opened by an age identity file instead of a token
just yubikey-onboard -- --from-backup /mnt/usb/backup/master-secret.key.age \
  --age-identity /mnt/usb/offline-identity.txt

# Rotate a token whose PINs were set on an earlier day and stay as they are
just yubikey-onboard -- --from-backup /mnt/usb/backup --allow-default-pins

# Force RSA 4096 for an older YubiKey
just yubikey-onboard -- --algo rsa4096
```

## Nix Package

The script is packaged as a Nix derivation at `flake/packages.nix` and exposed as `packages.<system>.yubikey-onboard` for `x86_64-linux` and `aarch64-linux`. All runtime dependencies (gnupg, yubikey-manager, pam_u2f, age, age-plugin-yubikey, ssh-to-age, pinentry-curses, openssh, util-linux) are pinned via the flake lockfile. Building the package runs shellcheck over the script, and the `yubikey-onboard-builds` check builds it in CI.

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
| 3-6 | Per key | **Provision YubiKey**, reset, keytocard and its verification, PINs for OpenPGP and PIV, U2F, age identity |
| 7 | Once | **SSH Keygrip**, extract authentication subkey keygrip |
| 8 | Once | **Public Key Import**, import into persistent keyring |
| 9 | Once | **Encrypted Backup**, age-encrypt the master key and subkeys exports and remove the plaintext |
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

A default run leaves no plaintext behind, so the usual input is one of the two
encrypted copies. The path may name either file, or the directory that holds
them:

| Input | Opened with |
|-------|-------------|
| `master-secret.key.pass.age` | the backup passphrase, which `age` asks for |
| `master-secret.key.age` | an identity file given with `--age-identity` or at the prompt, or the YubiKey in the reader through `age-plugin-yubikey` |
| `master-secret.key` | nothing, since it is plaintext |

Given a directory, the script takes a plaintext `master-secret.key` when one is
there, and otherwise asks which encrypted copy to open when both exist. The
token copy opens only with a YubiKey that was provisioned when the backup was
written, so a rotation onto a blank replacement token starts from the passphrase
copy, or from the token copy with an older token in the reader first. The script
pauses after decryption so that the tokens can be swapped.

An encrypted backup is decrypted into the ramfs GNUPGHOME and nowhere else. When
fresh subkeys are generated, the new exports are written in the ramfs as well,
and the encrypted backup phase writes the new copies to the backup directory. No
plaintext reaches the medium in that flow. A plaintext input stays where it is
during the run, and the encrypted backup phase encrypts and removes it at the
end.

Every file the rotation replaces is written beside its target as
`<target>.new`, read back, and moved into place only after that. A failed or
cancelled export leaves the existing backup as it was. The new token copy is
encrypted to the YubiKeys provisioned in this run and to any `--age-recipient`,
and the recipients of the copy it replaces are not carried over, so a token from
an earlier run keeps opening the backup only when its recipient is passed again.

This mode is intended for:

- **Key rotation**. Expired subkeys, generate new ones from the same master
- **Replacement YubiKey**. Lost/damaged key, provision a new one with existing subkeys

```bash
{{#include ../../../scripts/yubikey-onboard.sh:from-backup}}
```

### Phase 2: Master Key Backup

Exports the master secret key, subkeys, public key, and revocation certificate to a user-specified directory (or the path from `--backup-dir`). Each export is written as `<target>.new`, listed with gpg, and compared with the fingerprints in the keyring before it takes its final name. Displays SHA256 checksums for verification. Both secret exports are plaintext from this point until the encrypted backup phase. **The script will not proceed until backups are confirmed** -- this is a hard gate because `keytocard` in Phase 3 is irreversible.

This phase is skipped in `--from-backup` mode since the backup already exists.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:backup}}
```

### Phase 3: Move Subkeys to YubiKey

The script runs `keytocard` itself. The temporary GNUPGHOME sits on a ramfs
inside a mount namespace that only the script's own process tree can see, so a
`gpg --edit-key` typed into a second terminal finds an empty directory and no
key. Everything that touches the keyring therefore runs from inside the script.

The subkey for each slot is chosen by capability, and the newest usable one
wins. Position in the key listing is not used, since a rotated key carries its
expired subkeys ahead of the new ones. One `gpg --edit-key` session runs for
each subkey, selected by fingerprint. The script answers gpg's questions by the
keyword gpg announces on its status channel, and a question it has no answer
for ends the session with the key unchanged. gpg-agent asks for the master key
passphrase and the OpenPGP admin PIN through pinentry on the same terminal, and
neither passes through the script. When the applet already holds keys, the
script lists them and asks before anything is replaced.

After the three sessions the script reads `gpg --card-status` and compares the
fingerprint in each slot with the subkey chosen for it. An empty slot or a slot
holding another key is a hard failure. The script then offers an interactive
`gpg --edit-key` session on the same terminal, inside the same namespace, prints
the three `key <fingerprint>` commands with their slots, and checks the card
again afterwards. Declining stops the run before any PIN is changed and before
any export is removed, and the error says whether plaintext exports are still on
the backup medium.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:keytocard}}
```

### Per-YubiKey Provisioning (Phases 3-6)

For each YubiKey, the script runs:

- **Reset**. Optionally factory reset the OpenPGP and FIDO2 applets
- **Phase 3**: `keytocard` for each subkey, then the fingerprint check against the card
- **Phase 4**: Change the OpenPGP user PIN (`123456`) and admin PIN (`12345678`), then the PIV PIN (`123456`), PUK (`12345678`) and management key, all via `ykman`
- **Phase 5**: Register a U2F credential with `pamu2fcfg -n -o pam://yubi`
- **Phase 6**: Generate an age identity with `age-plugin-yubikey --generate` (touch: always, PIN: once)

Every prompt in Phase 4 defaults to yes. The script cannot ask a token whether
a PIN is still the factory one without spending a retry, so it tracks which
changes ran. A credential that was not changed stops the run, unless
`--allow-default-pins` is given, which is meant for a token whose PINs were set
on an earlier day. The credentials left alone are then listed at the end of the
run. Two failed attempts at one credential also stop the run, since a third
wrong entry of the current value can block it.

The PIV applet is changed in Phase 4 so that the age identity Phase 6 writes
into it is never guarded by the factory PIN. The management key is replaced with
a random one stored on the token behind the PIN, which is the form
`age-plugin-yubikey` accepts.

After the first YubiKey is provisioned, the script asks whether to provision another (or provisions exactly `--key-count` keys). It restores the subkeys from the master key export between each `keytocard` pass.

### Post-Provisioning (Phases 7-9)

- **Phase 7**: Extract the authentication subkey's keygrip for SSH and export the SSH public key (same for all keys since they share the same GPG key)
- **Phase 8**: Import the public key into the persistent `~/.gnupg` keyring and set ultimate trust

### Encrypted Key Backup

Runs after every YubiKey is provisioned, and the ordering is forced rather than
chosen. The plaintext backup has to exist before `keytocard` in Phase 3, since
that move is irreversible, and it has to survive the provisioning loop because
subkeys are re-imported from it between each key. The age recipients do not
exist until Phase 6 has run for a token. There is no earlier point at which both
are true.

Both secret exports go through the same function, `master-secret.key` first and
`subkeys-secret.key` after it. Two files are written for each, because `age`
refuses `-p` and `-r` together:

| File | Opens with |
|------|------------|
| `master-secret.key.age`, `subkeys-secret.key.age` | any provisioned YubiKey, or an extra `--age-recipient` |
| `master-secret.key.pass.age`, `subkeys-secret.key.pass.age` | the passphrase entered during this phase |

`age` asks for the passphrase twice to encrypt each export and once more to
verify it, which makes six entries in a default run.

The passphrase copy is not redundancy for its own sake. A master key backup
exists precisely to survive losing every token, so encrypting it *only* to those
tokens makes it worthless in the situation it was created for. `--no-age-passphrase`
declines it.

Each copy is written as `<name>.new`, decrypted, compared byte for byte with the
plaintext, and moved into place only after that, so a copy from an earlier run
is never replaced by one that has not been opened. A plaintext export is removed
only once one of its copies has passed that comparison in the same run. A failed
verification keeps the plaintext and says so, and the run then ends with a
non-zero exit status and the list of exports that are still plaintext.
`--keep-plaintext` retains the plaintext even on success, and `--no-age-backup`
skips the phase entirely.

A plaintext `subkeys-secret.key` that an earlier run left in the backup
directory is handled here too. It is encrypted with the rest, or removed once
the new encrypted copy holds every key in it.

#### What `shred` Removes

The plaintext is removed with `shred -u`, which overwrites the blocks of a file
in place before unlinking it. That removes the data only where an overwrite
lands on the blocks that held it:

- On the ramfs the temporary GNUPGHOME lives on, the overwrite is effective, and
  the pages are freed when the script exits.
- On flash media, which covers USB sticks, SD cards and SSDs, the controller
  remaps writes for wear levelling. The old blocks stay on the device until the
  controller reuses them, and they can be read from the raw flash.
- On a copy-on-write filesystem such as btrfs, an overwrite is written to new
  blocks and the old ones are released without being cleared. Snapshots keep
  them for as long as the snapshot exists.

`shred` reports success in all three cases. The recommendation follows from
that. Key material that must not persist is worked on in the ramfs, which the
script already does for the keyring and for everything a `--from-backup` run
decrypts. A first run cannot avoid plaintext exports on the backup medium,
since they have to exist before `keytocard` and the age recipients do not exist
until after it. A plaintext copy that has touched a USB stick is therefore
treated as exposed to anyone who later holds that stick. The backup medium
should be an encrypted volume, such as a LUKS container, or a stick that is kept
or destroyed and never reused for anything else. The master key passphrase from
Phase 1 is what protects the export while it sits there, which is one more
reason not to pass `--no-passphrase`.

Verifying the token copy needs the inserted YubiKey's PIN and a touch, and can
only test the token currently in the reader, which after a multi-key run is the
last one provisioned. The other tokens are the same mechanism and the same
ciphertext, but this phase has not proved them.

```bash
{{#include ../../../scripts/yubikey-onboard.sh:age-backup}}
```

### Phase 10: Summary Output

Prints all values ready to paste into the NixOS host configurations:

- `sshKeygrips`, GPG keygrip for SSH authentication (shared across all keys)
- `u2fMappings`, one U2F credential per YubiKey
- `ageIdentityStubs`, age identity block for sops-nix (primary key)
- Git signing key fingerprint
- SSH public key for GitHub/servers
- age recipients for all provisioned keys (add all to `.sops.yaml` for redundancy)

A copy is saved in the backup directory as `yubikey-onboard-summary-*.txt`, since it carries the keygrip, the age recipients and the U2F credential lines that the host configuration needs later. In a `--from-backup` run the backup directory is the one the backup was read from.

The summary is never written to the working directory, which is often a public
checkout. When the backup directory is no longer there at the end of the run, as
when the medium was unmounted, the file goes to a new directory with mode 0700
under `$XDG_RUNTIME_DIR`, or under `/tmp` when that is unset, and the script
prints its path. That directory does not survive a reboot. A dry run writes no
summary and prints the directory a real run would use.

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
- Phase 4 changes the OpenPGP and PIV credentials and refuses to finish with one
  left unchanged unless `--allow-default-pins` is given. The FIDO2 applet ships
  without a PIN, and the script does not set one
- `shred` cannot promise removal on flash media or on a copy-on-write
  filesystem. See [What `shred` Removes](#what-shred-removes)
- Names, email addresses, paths and every other prompted or flag value are
  refused when they contain a newline or another control character, since some
  of them are fed to gpg as commands
- The GPG configuration follows [drduh's hardened settings](https://github.com/drduh/config/blob/master/gpg.conf)
- In `--from-backup` mode, the master key is loaded into the same ramfs GNUPGHOME
  from the backup, so it still never persists to disk. An encrypted backup is
  decrypted there and nowhere else
