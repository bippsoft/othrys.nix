#!/usr/bin/env bash
# scripts/yubikey-onboard.sh
#
# Generates PGP keys (following drduh's guide), moves subkeys to YubiKey,
# registers U2F credentials, sets up age-plugin-yubikey for sops-nix,
# and outputs all values needed for the NixOS configuration.
#
# Usage: bash scripts/yubikey-onboard.sh [OPTIONS]
#   Run with --help for full option list.

set -euo pipefail

# Every file this script writes holds key material, a keygrip, or an age
# recipient. The backup directory is chmod 700 before anything lands in it, and
# that stops protecting the contents the moment the directory is copied or
# moved, so the mode goes on the files themselves.
umask 077

# Re-exec inside a private mount namespace so the temporary GNUPGHOME can sit on
# ramfs. The script has always claimed RAM-backed storage with no disk traces
# and has always used /dev/shm, which is tmpfs, and tmpfs pages are swappable.
# On a host with active swap the master key can therefore reach disk while it
# exists. ramfs pages are never swapped.
#
# unshare -Urm needs no privilege, so this costs nothing where unprivileged user
# namespaces are available and degrades to a warning where they are not. The
# namespace also removes the cleanup problem, since the mount dies with the
# process and cannot be left behind by a failed unmount.
#
# `slave` propagation rather than `private`, because the script asks the
# operator to swap YubiKeys and mount removable media mid-run. Host mounts made
# after this point must stay visible, while the ramfs must not leak out.
if [[ -z ${YUBIKEY_ONBOARD_NS:-} ]]; then
  reexec=true
  for arg in "$@"; do
    # These modes touch no key material and need no namespace.
    case "$arg" in
    --verify | -h | --help) reexec=false ;;
    esac
  done
  if $reexec && command -v unshare >/dev/null 2>&1 &&
    unshare -Urm --propagation slave true 2>/dev/null; then
    export YUBIKEY_ONBOARD_NS=1
    # Through the running bash, since the file is not executable when the
    # script is started as `bash scripts/yubikey-onboard.sh`.
    exec unshare -Urm --propagation slave "$BASH" "$0" "$@"
  fi
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Minimum YubiKey firmware for ed25519 support
MIN_ECC_FIRMWARE="5.2.3"

# Defaults. Name and email deliberately have none. They were `alice` and
# `alice@example.com`, and pressing Enter through the prompts minted that as a
# permanent PGP identity. Flags are read before prompting, so the constants had
# no reachable use once empty entry is refused.
DEFAULT_EXPIRY="2y"
DEFAULT_U2F_ORIGIN="pam://yubi"

# Options
DRY_RUN=false
VERIFY_MODE=false
OPT_BACKUP_DIR=""
OPT_FROM_BACKUP=""
OPT_NAME=""
OPT_EMAIL=""
OPT_EXPIRY=""
OPT_ALGO=""
OPT_KEY_COUNT=""
OPT_FORCE_VOLATILE=false
OPT_NO_PASSPHRASE=false
OPT_NO_AGE_BACKUP=false
OPT_NO_AGE_PASSPHRASE=false
OPT_KEEP_PLAINTEXT=false
OPT_AGE_RECIPIENTS=()
OPT_AGE_IDENTITY=""
OPT_ALLOW_DEFAULT_PINS=false

# State, populated during execution
SECURE_TMPDIR=""
RAMFS_MOUNT=""
TEMP_GNUPGHOME=""
KEY_FINGERPRINT=""
SSH_KEYGRIP=""
SSH_PUBKEY=""
BACKUP_DIR=""
KEY_ALGO="ed25519"

# The plaintext exports that exist during the run. They sit in the backup
# directory on a first run and inside the ramfs when an encrypted backup was
# imported, and the encrypted backup phase reads them from wherever they are.
MASTER_PLAINTEXT=""
SUBKEYS_PLAINTEXT=""
# A plaintext file --from-backup read that a re-export has since replaced.
IMPORTED_PLAINTEXT=""

# The subkey chosen for each card slot, and what the card reports back.
SUBKEY_FPR_SIGN="" # gitleaks:allow (an empty variable that later holds a public fingerprint)
SUBKEY_FPR_ENCR=""
SUBKEY_FPR_AUTH=""
CARD_FPR_SIGN=""
CARD_FPR_ENCR=""
CARD_FPR_AUTH=""

# The token in the reader. A token that reports no serial number is recorded
# under NO_SERIAL, so no message is ever built from an empty string.
NO_SERIAL="unreported"
CURRENT_SERIAL=""
CURRENT_FIRMWARE=""

# Credentials left at whatever value they had when the run started, and
# plaintext exports the run could not remove. Both are reported at the end.
UNCHANGED_CREDENTIALS=()
PLAINTEXT_LEFT=()

# Per-YubiKey state (indexed by key number)
YUBIKEY_SERIALS=()
U2F_CREDENTIALS=()
AGE_IDENTITIES=()
AGE_RECIPIENTS=()
AGE_FULL_OUTPUTS=()
NUM_KEYS=0

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
dry_run_skip() { echo -e "${YELLOW}[DRY-RUN]${NC} Skipping: $*"; }
header() {
  echo ""
  echo -e "${BOLD}${CYAN}============================================================${NC}"
  echo -e "${BOLD}${CYAN} $*${NC}"
  echo -e "${BOLD}${CYAN}============================================================${NC}"
  echo ""
}

prompt_yn() {
  local question="$1"
  local default="${2:-n}"
  local prompt
  if [[ $default == "y" ]]; then
    prompt="[Y/n]"
  else
    prompt="[y/N]"
  fi
  while true; do
    read -rp "$(echo -e "${BOLD}$question $prompt${NC} ")" answer
    answer="${answer:-$default}"
    case "${answer,,}" in
    y | yes) return 0 ;;
    n | no) return 1 ;;
    *) echo "Please answer y or n." ;;
    esac
  done
}

# Prompted values and option values end up in a PGP user ID, in a command
# stream fed to gpg, and in paths. A newline in any of them would be read as
# the start of the next command, and other control characters change what the
# terminal shows, so both are refused where the value enters the script.
is_clean_text() {
  [[ $1 != *[[:cntrl:]]* ]]
}

# An option that takes a value and is given last would otherwise trip `set -u`
# on $2 and end the script with an unbound variable message.
require_value() {
  if [[ $# -lt 2 ]]; then
    error "Option $1 needs a value."
    exit 1
  fi
  if ! is_clean_text "$2"; then
    error "The value given to $1 contains a newline or a control character."
    exit 1
  fi
}

prompt_value() {
  local question="$1"
  local default="$2"
  local result
  while true; do
    result=""
    read -rp "$(echo -e "${BOLD}$question${NC} [${default}]: ")" result || true
    result="${result:-$default}"
    if is_clean_text "$result"; then
      echo "$result"
      return 0
    fi
    echo "Control characters are not accepted. Enter the value again." >&2
  done
}

# For values with no meaningful default, where accepting an empty answer writes
# something permanent. Loops rather than exiting, since the operator is already
# partway through provisioning and re-running costs a YubiKey reset.
prompt_required() {
  local question="$1"
  local result
  while true; do
    result=""
    # At end of input there is nobody left to ask, and looping would never end.
    if ! read -rp "$(echo -e "${BOLD}$question${NC}: ")" result && [[ -z $result ]]; then
      echo "No input is available for a value that has no default." >&2
      return 1
    fi
    if ! is_clean_text "$result"; then
      echo "Control characters are not accepted. Enter the value again." >&2
      continue
    fi
    if [[ -n ${result//[[:space:]]/} ]]; then
      echo "$result"
      return 0
    fi
    echo "This cannot be empty. It becomes part of a permanent PGP identity." >&2
  done
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Provision one or more YubiKeys with PGP keys, U2F credentials, and age identity.

Modes:
  (default)            Generate new PGP keys and provision YubiKey(s)
  --from-backup <path> Import an existing master key backup and provision YubiKey(s)
                       (for key rotation or replacement YubiKeys). The path is a
                       backup directory, master-secret.key.age,
                       master-secret.key.pass.age, or a plaintext master-secret.key
  --verify             Check the currently inserted YubiKey's health and config

Key identity (skip interactive prompts):
  --name <name>        Real name for the PGP key
  --email <email>      Email address for the PGP key
  --expiry <duration>  Subkey expiry period (default: $DEFAULT_EXPIRY)

Both are prompted for when the flag is absent, and neither may be empty. They
become a permanent PGP identity, so there is no default.

Provisioning options:
  --backup-dir <path>  Master key backup directory (required for provisioning)
  --force-volatile     Allow a backup directory the host may not persist
  --no-passphrase      Leave the master key unprotected (escape hatch)
  --algo <algorithm>   Force key algorithm: ed25519 or rsa4096 (auto-detected by default)
  --key-count <n>      Number of YubiKeys to provision (skips the "provision another?" prompt)
  --allow-default-pins Finish even when a PIN, PUK or management key was not changed
  --age-identity <file>
                       age identity file that opens master-secret.key.age, for
                       --from-backup (default: the YubiKey in the reader)
  --dry-run            Walk through all phases. Touches no YubiKey and no keyring,
                       and writes no file

Encrypted backup (on by default, runs after the YubiKeys are provisioned):
  --age-recipient <r>  Extra age recipient, repeatable
  --no-age-passphrase  Skip the passphrase-encrypted copy
  --keep-plaintext     Keep the plaintext exports after the encrypted copies verify
  --no-age-backup      Do not produce encrypted copies at all

Two files are written for each export, since age refuses a passphrase and
recipients together. master-secret.key.age opens with a provisioned YubiKey,
master-secret.key.pass.age with the passphrase, and subkeys-secret.key gets the
same pair. A plaintext export is removed only after a copy of it has been
decrypted and compared in the same run.

The summary is saved in the backup directory, and never in the working
directory.

General:
  -h, --help           Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --verify)
    VERIFY_MODE=true
    shift
    ;;
  --from-backup)
    require_value "$@"
    OPT_FROM_BACKUP="$2"
    shift 2
    ;;
  --backup-dir)
    require_value "$@"
    OPT_BACKUP_DIR="$2"
    shift 2
    ;;
  --force-volatile)
    OPT_FORCE_VOLATILE=true
    shift
    ;;
  --no-passphrase)
    OPT_NO_PASSPHRASE=true
    shift
    ;;
  --age-recipient)
    require_value "$@"
    OPT_AGE_RECIPIENTS+=("$2")
    shift 2
    ;;
  --age-identity)
    require_value "$@"
    OPT_AGE_IDENTITY="$2"
    shift 2
    ;;
  --allow-default-pins)
    OPT_ALLOW_DEFAULT_PINS=true
    shift
    ;;
  --no-age-passphrase)
    OPT_NO_AGE_PASSPHRASE=true
    shift
    ;;
  --keep-plaintext)
    OPT_KEEP_PLAINTEXT=true
    shift
    ;;
  --no-age-backup)
    OPT_NO_AGE_BACKUP=true
    shift
    ;;
  --name)
    require_value "$@"
    OPT_NAME="$2"
    shift 2
    ;;
  --email)
    require_value "$@"
    OPT_EMAIL="$2"
    shift 2
    ;;
  --expiry)
    require_value "$@"
    OPT_EXPIRY="$2"
    shift 2
    ;;
  --algo)
    require_value "$@"
    OPT_ALGO="$2"
    if [[ $OPT_ALGO != "ed25519" && $OPT_ALGO != "rsa4096" ]]; then
      error "Invalid algorithm: $OPT_ALGO (must be ed25519 or rsa4096)"
      exit 1
    fi
    shift 2
    ;;
  --key-count)
    require_value "$@"
    OPT_KEY_COUNT="$2"
    if ! [[ $OPT_KEY_COUNT =~ ^[1-9][0-9]*$ ]]; then
      error "Invalid key count: $OPT_KEY_COUNT (must be a positive integer)"
      exit 1
    fi
    shift 2
    ;;
  -h | --help)
    usage
    ;;
  *)
    error "Unknown option: $1"
    error "Run with --help for the option list."
    exit 1
    ;;
  esac
done

check_yubikey() {
  # A dry run talks to no device, so there is nothing to detect.
  if $DRY_RUN; then
    return 0
  fi
  if ! ykman info &>/dev/null; then
    error "No YubiKey detected. Please insert your YubiKey and try again."
    return 1
  fi
}

# One field of `ykman info`, or nothing when the token does not print it. The
# Security Key series and tokens with the serial hidden print no serial line,
# and under pipefail a grep that matched nothing ended the script without a
# message.
yubikey_info_field() {
  ykman info 2>/dev/null |
    awk -v field="$1" 'index($0, field) == 1 {print $NF; exit}' || true
}

# Read the serial and firmware of the token in the reader. A dry run reads
# nothing and assumes a current firmware, so its output carries no real serial.
read_yubikey() {
  if $DRY_RUN; then
    CURRENT_SERIAL="dry-run"
    CURRENT_FIRMWARE="$MIN_ECC_FIRMWARE"
    return 0
  fi
  CURRENT_SERIAL=$(yubikey_info_field "Serial number")
  CURRENT_FIRMWARE=$(yubikey_info_field "Firmware version")
  if [[ -z $CURRENT_SERIAL ]]; then
    CURRENT_SERIAL="$NO_SERIAL"
  fi
}

# ykman reaches the token through pcscd, and scdaemon keeps the card open once
# gpg has used it. Stopping scdaemon hands the card back before a ykman call.
# gpg starts it again on its next card operation.
release_card() {
  gpgconf --kill scdaemon 2>/dev/null || true
}

# Compare firmware versions: returns 0 if $1 >= $2
version_gte() {
  local i
  local -a ver1 ver2
  IFS=. read -ra ver1 <<<"$1"
  IFS=. read -ra ver2 <<<"$2"
  for ((i = 0; i < ${#ver2[@]}; i++)); do
    if ((${ver1[i]:-0} < ${ver2[i]:-0})); then
      return 1
    elif ((${ver1[i]:-0} > ${ver2[i]:-0})); then
      return 0
    fi
  done
  return 0
}

# Write the hardened gpg.conf + gpg-agent.conf into $GNUPGHOME (matching yubikey.nix).
write_gnupg_config() {
  cat >"$GNUPGHOME/gpg.conf" <<'GPGCONF'
personal-cipher-preferences AES256 AES192 AES
personal-digest-preferences SHA512 SHA384 SHA256
personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
cert-digest-algo SHA512
s2k-digest-algo SHA512
s2k-cipher-algo AES256
charset utf-8
fixed-list-mode
no-comments
no-emit-version
keyid-format 0xlong
list-options show-uid-validity
verify-options show-uid-validity
with-fingerprint
require-cross-certification
no-symkey-cache
use-agent
throw-keyids
GPGCONF

  cat >"$GNUPGHOME/gpg-agent.conf" <<AGENTCONF
pinentry-program $(command -v pinentry-curses || command -v pinentry-tty || command -v pinentry)
default-cache-ttl 60
max-cache-ttl 120
AGENTCONF

  # The same setting yubikey.nix writes. ykman needs pcscd, and scdaemon's own
  # CCID driver cannot share the reader with it.
  cat >"$GNUPGHOME/scdaemon.conf" <<'SCDCONF'
disable-ccid
SCDCONF
}

# Create the temporary GNUPGHOME on ramfs (or tmpfs if unavailable) and start
# an agent for it. A dry run creates the directory, so the mount is exercised,
# and starts no agent since nothing will talk to one.
setup_gnupghome() {
  setup_secure_tmpdir
  TEMP_GNUPGHOME=$(mktemp -d "$SECURE_TMPDIR/gnupg_XXXXXXXXXX")
  chmod 700 "$TEMP_GNUPGHOME"
  export GNUPGHOME="$TEMP_GNUPGHOME"

  if [[ -n $RAMFS_MOUNT ]]; then
    info "Temporary GNUPGHOME is on ramfs, which is never written to disk or swap."
  fi

  write_gnupg_config

  if ! $DRY_RUN; then
    gpgconf --kill gpg-agent 2>/dev/null || true
    gpg-agent --daemon 2>/dev/null || true
  fi
}

cleanup() {
  if [[ -n $TEMP_GNUPGHOME && -d $TEMP_GNUPGHOME ]]; then
    # Kill any gpg-agent running for the temp home. A dry run started none.
    if ! $DRY_RUN; then
      GNUPGHOME="$TEMP_GNUPGHOME" gpgconf --kill gpg-agent 2>/dev/null || true
    fi
    rm -rf "$TEMP_GNUPGHOME"
    if [[ -n $RAMFS_MOUNT ]]; then
      info "Cleaned up temporary GNUPGHOME (ramfs, never written to disk or swap)."
    else
      # Says what is true rather than what we would like to be true. tmpfs
      # pages are swappable, so on a host with active swap the key may have
      # reached disk. Encrypted swap bounds the exposure, and the script has no
      # way to confirm the host has any.
      info "Cleaned up temporary GNUPGHOME (tmpfs; pages may have reached swap)."
    fi
  fi
  # The namespace takes the ramfs mount with it when this process exits. It is
  # unmounted here all the same, since a mountpoint that is still in use cannot
  # be removed and would be left behind as an empty directory.
  if [[ -n $RAMFS_MOUNT && -d $RAMFS_MOUNT ]]; then
    umount "$RAMFS_MOUNT" 2>/dev/null || true
    rmdir "$RAMFS_MOUNT" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Where the master key lives while it exists. ramfs when the re-exec at the top
# of this script put us in a mount namespace, tmpfs otherwise.
setup_secure_tmpdir() {
  [[ -n $SECURE_TMPDIR ]] && return 0

  if [[ -n ${YUBIKEY_ONBOARD_NS:-} ]]; then
    local candidate
    candidate=$(mktemp -d)
    if mount -t ramfs -o mode=700 ramfs "$candidate" 2>/dev/null; then
      RAMFS_MOUNT="$candidate"
      SECURE_TMPDIR="$candidate"
      return 0
    fi
    rmdir "$candidate" 2>/dev/null || true
  fi

  SECURE_TMPDIR="/dev/shm"
  warn "Could not mount ramfs; falling back to /dev/shm, which is tmpfs."
  if [[ -s /proc/swaps ]] && [[ $(wc -l </proc/swaps) -gt 1 ]]; then
    warn "This host has active swap, so the master key may be paged to disk"
    warn "while it exists. Encrypted swap bounds that; unencrypted swap does not."
  fi
}

# ANCHOR: preflight
phase_preflight() {
  header "Phase 0: Preflight Checks"

  # Check required tools
  local tools=("gpg" "ykman" "pamu2fcfg" "age" "age-plugin-yubikey" "ssh-to-age")
  local missing=()
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required tools: ${missing[*]}"
    echo "  These should be available when othrys.services.security.yubikey.enable = true"
    echo "  You can also run: nix shell nixpkgs#{${missing[*]// /,}}"
    exit 1
  fi
  success "All required tools found."

  # Detect initial YubiKey (for firmware/algorithm check)
  check_yubikey
  read_yubikey
  local firmware="$CURRENT_FIRMWARE"

  if $DRY_RUN; then
    dry_run_skip "ykman info (assuming firmware $firmware)"
  else
    info "YubiKey detected:"
    echo "  Serial:   $CURRENT_SERIAL"
    echo "  Firmware: ${firmware:-unreported}"
  fi

  # Determine key algorithm
  if [[ -z $firmware && -z $OPT_ALGO ]]; then
    error "This token reports no firmware version, so the key algorithm cannot be chosen."
    error "Pass --algo ed25519 or --algo rsa4096 to choose one."
    exit 1
  elif [[ -n $OPT_ALGO ]]; then
    KEY_ALGO="$OPT_ALGO"
    info "Algorithm forced via --algo: $KEY_ALGO"
    if [[ $KEY_ALGO == "ed25519" && -n $firmware ]] && ! version_gte "$firmware" "$MIN_ECC_FIRMWARE"; then
      warn "Firmware $firmware may not support ed25519 (requires >= $MIN_ECC_FIRMWARE)."
      warn "Proceeding anyway as --algo was explicitly set."
    fi
  elif version_gte "$firmware" "$MIN_ECC_FIRMWARE"; then
    success "Firmware supports ed25519/cv25519."
    KEY_ALGO="ed25519"
  else
    warn "Firmware $firmware does not support ed25519 (requires >= $MIN_ECC_FIRMWARE)."
    warn "Falling back to RSA 4096."
    KEY_ALGO="rsa4096"
  fi
}
# ANCHOR_END: preflight

# Detect the currently inserted YubiKey and optionally reset its applets.
# Called once per YubiKey during the provisioning loop.
detect_and_reset_yubikey() {
  local key_num="$1"

  check_yubikey
  read_yubikey
  YUBIKEY_SERIALS+=("$CURRENT_SERIAL")

  info "YubiKey #$((key_num + 1)) detected (serial: $CURRENT_SERIAL)"

  if prompt_yn "Factory reset the OpenPGP applet? (destroys existing PGP keys on card)"; then
    if $DRY_RUN; then
      dry_run_skip "ykman openpgp reset"
    else
      release_card
      ykman openpgp reset
      success "OpenPGP applet reset."
    fi
  fi

  if prompt_yn "Factory reset the FIDO2 applet? (destroys existing FIDO2/U2F credentials)"; then
    if $DRY_RUN; then
      dry_run_skip "ykman fido reset"
    else
      release_card
      ykman fido reset
      success "FIDO2 applet reset."
    fi
  fi
}

# Restore secret subkeys from backup after keytocard has replaced them with stubs.
# This allows provisioning the same subkeys onto another YubiKey.
restore_subkeys() {
  if $DRY_RUN; then
    dry_run_skip "gpg --import master-secret.key (restore subkeys for next YubiKey)"
    return
  fi

  info "Restoring subkeys from backup for next YubiKey..."

  if [[ -z $MASTER_PLAINTEXT || ! -s $MASTER_PLAINTEXT ]]; then
    error "The master key export is missing, so the subkeys cannot be restored."
    error "Expected it at: ${MASTER_PLAINTEXT:-(not set)}"
    exit 1
  fi

  # Delete the stub keys first so GPG will accept the full import
  gpg --batch --yes --delete-secret-and-public-key "$KEY_FINGERPRINT" 2>/dev/null || true

  # Re-import the full secret key (master + subkeys)
  gpg --batch --import "$MASTER_PLAINTEXT" 2>/dev/null || {
    error "Failed to restore subkeys from backup."
    exit 1
  }

  success "Subkeys restored from backup."
}

# ANCHOR: keygen
phase_generate_keys() {
  header "Phase 1: PGP Master Key Generation"

  info "Master key will be generated in a temporary GNUPGHOME held in memory."
  echo ""

  # Prompt for key details (skip if provided via CLI)
  local real_name email expiry
  if [[ -n $OPT_NAME ]]; then
    real_name="$OPT_NAME"
  else
    real_name=$(prompt_required "Real name for the key")
  fi
  if [[ -n $OPT_EMAIL ]]; then
    email="$OPT_EMAIL"
  else
    email=$(prompt_required "Email address")
  fi
  if [[ -n $OPT_EXPIRY ]]; then
    expiry="$OPT_EXPIRY"
  else
    expiry=$(prompt_value "Subkey expiry (e.g., 2y, 1y, 6m)" "$DEFAULT_EXPIRY")
  fi
  info "Key identity: $real_name <$email> (subkey expiry: $expiry)"

  setup_gnupghome

  if $DRY_RUN; then
    dry_run_skip "gpg --quick-gen-key \"$real_name <$email>\" $KEY_ALGO cert never"
    KEY_FINGERPRINT="DRY_RUN_FINGERPRINT_0000000000000000"
    dry_run_skip "gpg --quick-add-key (Sign, Encrypt, Authenticate subkeys)"
    info "Would generate master key + 3 subkeys with algorithm: $KEY_ALGO"
    info "Subkey expiry: $expiry"
    return
  fi

  info "Generating master key (Certify only)..."

  if [[ $KEY_ALGO == "ed25519" ]]; then
    gpg --batch --passphrase '' --quick-gen-key "$real_name <$email>" ed25519 cert never
  else
    gpg --batch --passphrase '' --quick-gen-key "$real_name <$email>" rsa4096 cert never
  fi

  # Get the fingerprint
  KEY_FINGERPRINT=$(gpg --list-keys --with-colons "$email" 2>/dev/null |
    awk -F: '/^fpr:/ {print $10; exit}')

  if [[ -z $KEY_FINGERPRINT ]]; then
    error "Failed to retrieve key fingerprint."
    exit 1
  fi

  success "Master key generated: $KEY_FINGERPRINT"

  # Generate subkeys
  info "Generating subkeys (Sign, Encrypt, Authenticate) with expiry: $expiry..."

  if [[ $KEY_ALGO == "ed25519" ]]; then
    gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" ed25519 sign "$expiry"
    gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" cv25519 encr "$expiry"
    gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" ed25519 auth "$expiry"
  else
    gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 sign "$expiry"
    gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 encr "$expiry"
    gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 auth "$expiry"
  fi

  success "Subkeys generated."
  echo ""
  gpg --list-keys --with-keygrip "$KEY_FINGERPRINT"

  echo ""
  set_master_passphrase
}

# Returns 0 when the master secret key on disk is passphrase-protected.
#
# gpg-agent's KEYINFO reports the protection state in field 8 of its S line,
# `C` for a key stored in the clear and `P` for a protected one. Verified
# against a freshly generated key both ways. This asks the agent about what is
# actually on disk rather than trusting that a passphrase dialog was completed,
# so it holds however the passphrase was set.
master_key_is_protected() {
  local grip
  grip=$(gpg --list-secret-keys --with-keygrip --with-colons "$KEY_FINGERPRINT" 2>/dev/null |
    awk -F: '/^grp/{print $10; exit}')
  [[ -n $grip ]] || return 1
  gpg-connect-agent "KEYINFO $grip" /bye 2>/dev/null |
    awk '/^S KEYINFO/{exit ($8 == "P") ? 0 : 1}'
}

# The master key and its subkeys are generated with --passphrase '', so until
# this runs the only copy of the identity is unprotected. This used to print a
# command to run in a second terminal followed by "Press Enter when done (or
# skip)", which advanced to the backup phase whether or not anything happened.
#
# Entry goes through gpg-agent's own pinentry on this terminal, so the
# passphrase lives in the agent's mlocked memory and never reaches a shell
# variable, the process environment or a trace. The gate below re-reads the
# on-disk state afterwards, so a cancelled or failed dialog cannot pass.
set_master_passphrase() {
  if $OPT_NO_PASSPHRASE; then
    warn "--no-passphrase given: the master key backup will be unprotected."
    warn "Anyone who reads the backup file holds your identity."
    return 0
  fi

  if $DRY_RUN; then
    dry_run_skip "gpg --edit-key $KEY_FINGERPRINT passwd"
    return 0
  fi

  warn "The master key is currently unprotected. Set a passphrase now."
  warn "It protects the backup, which is the only copy once subkeys move to the"
  warn "YubiKey and cannot be extracted again."
  echo ""

  while ! master_key_is_protected; do
    gpg --edit-key "$KEY_FINGERPRINT" passwd || true
    if master_key_is_protected; then
      break
    fi
    error "The master key is still unprotected."
    if prompt_yn "Try again?" "y"; then
      continue
    fi
    if prompt_yn "Continue with an UNPROTECTED master key?"; then
      warn "Proceeding with an unprotected master key at your request."
      return 0
    fi
    error "Refusing to continue to backup with an unprotected master key."
    error "Re-run with --no-passphrase if that is genuinely what you want."
    exit 1
  done

  success "Master key is passphrase-protected."
}
# ANCHOR_END: keygen

# ANCHOR: backup
# Warn when the backup target looks like somewhere the host will not persist.
#
# A filesystem-type test for tmpfs is not enough on its own. On a host using
# othrys.system.impermanence, /tmp is not a separate mount at all, it sits on a
# root filesystem that the boot wipe clears, and a tmpfs check sees nothing. So
# this looks at both the filesystem type and the well-known volatile paths, and
# still only warns, because no heuristic can enumerate what a given host keeps.
check_backup_target() {
  local target="$1" fstype="" volatile=false
  local parent="$target"
  # findmnt needs a path that exists, so walk up to the nearest one.
  while [[ -n $parent && ! -e $parent ]]; do parent=$(dirname "$parent"); done
  if command -v findmnt >/dev/null 2>&1 && [[ -e $parent ]]; then
    fstype=$(findmnt -no FSTYPE --target "$parent" 2>/dev/null || true)
  fi

  case "$fstype" in
  tmpfs | ramfs) volatile=true ;;
  esac
  case "$target" in
  /tmp/* | /tmp | /var/tmp/* | /var/tmp | /dev/shm/*) volatile=true ;;
  esac

  $volatile || return 0

  error "The backup directory looks volatile: $target"
  [[ -n $fstype ]] && error "  filesystem: $fstype"
  error "This is the only copy of a master key whose subkeys cannot be extracted"
  error "from the YubiKey again. If this location is cleared on reboot, the"
  error "identity is gone."
  if ! $OPT_FORCE_VOLATILE; then
    error "Pass --force-volatile if you know this location is kept."
    exit 1
  fi
  warn "--force-volatile given: continuing anyway."
}

# The fingerprints of the key in the keyring, primary and subkeys, one a line.
keyring_fingerprints() {
  gpg --list-keys --with-colons "$KEY_FINGERPRINT" 2>/dev/null |
    awk -F: '$1 == "fpr" {print $10}' | sort -u || true
}

# The fingerprints gpg finds in an export file. Nothing is imported.
file_fingerprints() {
  gpg --batch --show-keys --with-colons "$1" 2>/dev/null |
    awk -F: '$1 == "fpr" {print $10}' | sort -u || true
}

# True when every key in an export file is also in the keyring, which makes
# the file a subset of what a fresh export of the keyring holds.
export_is_covered() {
  local in_file
  in_file=$(file_fingerprints "$1")
  [[ -n $in_file ]] &&
    [[ -z $(comm -23 <(printf '%s\n' "$in_file") <(keyring_fingerprints)) ]]
}

# True for a path inside the temporary GNUPGHOME, which is memory and goes
# when the script exits. Everything else is treated as the backup medium.
in_gnupghome() {
  [[ -n $TEMP_GNUPGHOME && $1 == "$TEMP_GNUPGHOME"/* ]]
}

# Remove a plaintext export. shred overwrites the blocks of a file in place,
# which removes the data on the ramfs and on a filesystem that writes in place.
# Flash media remap blocks and copy-on-write filesystems write new ones, so the
# old contents can stay readable there and nothing run from here changes that.
# The operator is told once.
SHRED_WARNED=false
remove_plaintext() {
  local file="$1"
  [[ -e $file ]] || return 0
  shred -u "$file" 2>/dev/null || rm -f "$file"
  if in_gnupghome "$file"; then
    return 0
  fi
  if ! $SHRED_WARNED; then
    SHRED_WARNED=true
    warn "shred overwrites a file in place. Flash media and copy-on-write"
    warn "filesystems such as btrfs keep the old blocks, so treat the medium"
    warn "holding $(dirname "$file") as one that has carried the plaintext."
  fi
}

# Export one part of the key to <target>.new, read the new file back, and only
# then move it over <target>. A redirect straight onto the target truncates it
# before gpg has produced anything, and on a rotation the target is the only
# backup.
#
# Reading back means asking gpg to list the new file and comparing the
# fingerprints in it with the keyring. An export that stopped early, or one a
# cancelled passphrase prompt left empty, replaces nothing.
export_verified() {
  local kind="$1" target="$2"
  local new="$target.new"
  local block="-----BEGIN PGP PRIVATE KEY BLOCK-----" # gitleaks:allow (the armor header an export is compared with, not a key)
  local -a export_args=(--export-secret-keys)
  local want got first_line=""

  case "$kind" in
  subkeys) export_args=(--export-secret-subkeys) ;;
  public)
    export_args=(--export)
    block="-----BEGIN PGP PUBLIC KEY BLOCK-----"
    ;;
  esac

  rm -f "$new"
  if ! gpg --armor "${export_args[@]}" "$KEY_FINGERPRINT" >"$new"; then
    remove_plaintext "$new"
    error "gpg could not export the $kind key. $target was not changed."
    return 1
  fi

  want=$(keyring_fingerprints)
  got=$(file_fingerprints "$new")
  IFS= read -r first_line <"$new" || true
  if [[ $first_line != "$block" || -z $want || $got != "$want" ]]; then
    remove_plaintext "$new"
    error "The $kind export did not read back as the key in the keyring."
    error "$target was not changed."
    return 1
  fi

  mv -f "$new" "$target"
}

# Stop the run and say what it leaves behind. Every hard stop after the backup
# phase goes through here, so the operator always learns whether plaintext
# exports are still on the backup medium.
abort_run() {
  error "$1"
  if [[ -n $MASTER_PLAINTEXT && -e $MASTER_PLAINTEXT ]] && ! in_gnupghome "$MASTER_PLAINTEXT"; then
    error "Nothing was removed. The exports in $BACKUP_DIR are still plaintext."
    error "Encrypt them or remove them before the medium leaves your hands."
  elif [[ -n $BACKUP_DIR ]]; then
    error "Nothing was removed from $BACKUP_DIR."
  fi
  exit 1
}

phase_backup() {
  header "Phase 2: Master Key Backup"

  warn "After moving subkeys to the YubiKey, they CANNOT be extracted."
  warn "You MUST back up the master key now."
  echo ""

  if [[ -n $OPT_BACKUP_DIR ]]; then
    BACKUP_DIR="$OPT_BACKUP_DIR"
    info "Using backup directory from --backup-dir: $BACKUP_DIR"
  else
    # No default. This used to offer /tmp/yubikey-backup-<date>, which is
    # predictable, unencrypted, and on most hosts does not survive a reboot, so
    # pressing Enter put the only copy of a master key somewhere it could
    # vanish. The script cannot know what a given host persists, so the operator
    # names the destination.
    echo "Use removable media you can store somewhere safe, e.g. /run/media/you/backup."
    BACKUP_DIR=$(prompt_required "Backup directory")
  fi

  check_backup_target "$BACKUP_DIR"

  MASTER_PLAINTEXT="$BACKUP_DIR/master-secret.key"
  SUBKEYS_PLAINTEXT="$BACKUP_DIR/subkeys-secret.key"

  if $DRY_RUN; then
    dry_run_skip "mkdir -p $BACKUP_DIR"
    dry_run_skip "gpg --export-secret-keys -> $BACKUP_DIR/master-secret.key"
    dry_run_skip "gpg --export-secret-subkeys -> $BACKUP_DIR/subkeys-secret.key"
    dry_run_skip "gpg --export -> $BACKUP_DIR/public.key"
    dry_run_skip "cp revocation.cert -> $BACKUP_DIR/revocation.cert"
    info "Would export master key, subkeys, public key, and revocation cert."
    return
  fi

  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  info "Exporting keys to $BACKUP_DIR ..."

  # Master + subkeys, subkeys only, and the public key. Both secret exports
  # are plaintext until the encrypted backup phase has run.
  export_verified master "$MASTER_PLAINTEXT" || exit 1
  export_verified subkeys "$SUBKEYS_PLAINTEXT" || exit 1
  export_verified public "$BACKUP_DIR/public.key" || exit 1

  # Copy revocation cert
  local rev_cert="$GNUPGHOME/openpgp-revocs.d/$KEY_FINGERPRINT.rev"
  if [[ -f $rev_cert ]]; then
    cp "$rev_cert" "$BACKUP_DIR/revocation.cert"
  fi

  echo ""
  info "Backup checksums (SHA256):"
  sha256sum "$BACKUP_DIR"/*.key "$BACKUP_DIR"/*.cert 2>/dev/null || true

  echo ""
  echo -e "${RED}${BOLD}WARNING: Move these backups to secure offline storage NOW.${NC}"
  echo -e "${RED}${BOLD}The master key allows creating new subkeys and revoking old ones.${NC}"
  echo ""

  if ! prompt_yn "Have you saved the backups to secure storage?"; then
    error "Cannot continue without confirmed backups. Aborting."
    exit 1
  fi
}
# ANCHOR_END: backup

# ANCHOR: keytocard
# The newest usable subkey with one capability, read from a colon listing on
# stdin. A rotated key carries its expired subkeys beside the new ones, so the
# position in the listing says nothing about which subkey belongs in a slot.
subkey_for_capability() {
  awk -F: -v cap="$1" '
    $1 == "sub" { want = ($2 !~ /^[rei]$/ && index($12, cap) > 0); created = $6 + 0; next }
    $1 == "fpr" && want { if (created >= best) { best = created; fpr = $10 }; want = 0 }
    END { print fpr }'
}

select_card_subkeys() {
  local listing
  listing=$(gpg --list-keys --with-colons "$KEY_FINGERPRINT" 2>/dev/null || true)
  SUBKEY_FPR_SIGN=$(subkey_for_capability s <<<"$listing")
  SUBKEY_FPR_ENCR=$(subkey_for_capability e <<<"$listing")
  SUBKEY_FPR_AUTH=$(subkey_for_capability a <<<"$listing")
  if [[ -z $SUBKEY_FPR_SIGN || -z $SUBKEY_FPR_ENCR || -z $SUBKEY_FPR_AUTH ]]; then
    abort_run "The key lacks a usable signing, encryption or authentication subkey, so nothing was moved to the YubiKey."
  fi
}

# The fingerprints in the three card slots, as the card reports them. An empty
# slot reads as an empty string.
read_card_slots() {
  local line
  line=$(gpg --card-status --with-colons 2>/dev/null |
    awk -F: '$1 == "fpr" {print $2 ":" $3 ":" $4; exit}' || true)
  IFS=: read -r CARD_FPR_SIGN CARD_FPR_ENCR CARD_FPR_AUTH <<<"${line:-::}" || true
  CARD_FPR_SIGN="${CARD_FPR_SIGN^^}"
  CARD_FPR_ENCR="${CARD_FPR_ENCR^^}"
  CARD_FPR_AUTH="${CARD_FPR_AUTH^^}"
  [[ $CARD_FPR_SIGN =~ ^0+$ ]] && CARD_FPR_SIGN=""
  [[ $CARD_FPR_ENCR =~ ^0+$ ]] && CARD_FPR_ENCR=""
  [[ $CARD_FPR_AUTH =~ ^0+$ ]] && CARD_FPR_AUTH=""
  return 0
}

check_card_slot() {
  local label="$1" on_card="$2" expected="${3^^}"
  if [[ -z $on_card ]]; then
    error "$label slot is empty."
    return 1
  fi
  if [[ $on_card != "$expected" ]]; then
    error "$label slot holds $on_card, expected $expected."
    return 1
  fi
  success "$label slot holds $expected."
}

# True only when each slot holds the subkey chosen for it.
verify_card_slots() {
  local ok=true
  read_card_slots
  check_card_slot "Signature" "$CARD_FPR_SIGN" "$SUBKEY_FPR_SIGN" || ok=false
  check_card_slot "Encryption" "$CARD_FPR_ENCR" "$SUBKEY_FPR_ENCR" || ok=false
  check_card_slot "Authentication" "$CARD_FPR_AUTH" "$SUBKEY_FPR_AUTH" || ok=false
  $ok
}

# Run one `gpg --edit-key` session and answer its questions by the keyword gpg
# announces on its status channel. Feeding it lines in a fixed order goes wrong
# as soon as gpg asks one question more or fewer than expected, since every
# later answer then lands on the wrong question. Here a question with no known
# answer ends the session, and gpg leaves the key as it was.
#
# The first two arguments are the card slot and the answer to "replace the key
# in this slot". The rest are the commands for the edit prompt, in order.
#
# gpg runs in the foreground and keeps the terminal. gpg-agent asks for the key
# passphrase and the admin PIN through pinentry there, so neither passes
# through this script.
edit_key_scripted() {
  local slot="$1" replace="$2"
  shift 2
  local cmd_fifo="$GNUPGHOME/edit-commands" status_fifo="$GNUPGHOME/edit-status"
  local responder rc=0

  rm -f "$cmd_fifo" "$status_fifo"
  mkfifo "$cmd_fifo" "$status_fifo"

  (
    trap '' PIPE
    exec 3>"$cmd_fifo" 4<"$status_fifo"
    answered=0
    while IFS= read -r line <&4; do
      case "$line" in
      "[GNUPG:] GET_LINE keyedit.prompt")
        if [[ $# -gt 0 ]]; then
          reply="$1"
          shift
        else
          reply="quit"
        fi
        ;;
      "[GNUPG:] GET_LINE cardedit.genkeys.storekeytype") reply="$slot" ;;
      "[GNUPG:] GET_BOOL cardedit.genkeys.replace_key") reply="$replace" ;;
      "[GNUPG:] GET_BOOL keyedit.save.okay") reply="n" ;;
      "[GNUPG:] GET_"*)
        error "gpg asked a question this script has no answer for: ${line#\[GNUPG:\] }"
        exit 3
        ;;
      *) continue ;;
      esac
      # gpg repeats a question whose answer it did not accept. One subkey takes
      # five answers, so a dozen means the session is going in circles.
      answered=$((answered + 1))
      if ((answered > 12)); then
        error "gpg kept repeating its questions, so the session was ended."
        exit 3
      fi
      printf '%s\n' "$reply" >&3 || exit 3
    done
  ) &
  responder=$!

  gpg --command-fd 3 --status-fd 4 --edit-key "$KEY_FINGERPRINT" \
    3<"$cmd_fifo" 4>"$status_fifo" || rc=$?
  wait "$responder" || rc=$?
  rm -f "$cmd_fifo" "$status_fifo"
  return "$rc"
}

move_subkey_to_card() {
  local label="$1" slot="$2" fpr="$3" on_card="$4" replace="$5"
  if [[ $on_card == "${fpr^^}" ]]; then
    info "$label slot already holds this subkey."
    return 0
  fi
  info "Moving the $label subkey to slot $slot..."
  if ! edit_key_scripted "$slot" "$replace" "key $fpr" "keytocard" "save"; then
    warn "gpg did not finish moving the $label subkey."
  fi
}

phase_keytocard() {
  header "Phase 3: Move Subkeys to YubiKey"

  check_yubikey

  info "This step moves your subkeys to the YubiKey. This is IRREVERSIBLE."
  info "The subkeys in GNUPGHOME will be replaced with stubs."
  echo ""

  if $DRY_RUN; then
    dry_run_skip "gpg --edit-key $KEY_FINGERPRINT keytocard (3 subkeys)"
    dry_run_skip "gpg --card-status (compare the three slots with the subkeys)"
    info "Would move Sign, Encrypt, and Authenticate subkeys to YubiKey."
    return
  fi

  select_card_subkeys

  # gpg asks before it overwrites a slot, and the answer has to be decided
  # before the session starts.
  local replace="n"
  read_card_slots
  if [[ -n $CARD_FPR_SIGN$CARD_FPR_ENCR$CARD_FPR_AUTH ]]; then
    warn "The OpenPGP applet already holds keys:"
    echo "  Signature:      ${CARD_FPR_SIGN:-(empty)}"
    echo "  Encryption:     ${CARD_FPR_ENCR:-(empty)}"
    echo "  Authentication: ${CARD_FPR_AUTH:-(empty)}"
    if ! prompt_yn "Replace them with the subkeys of $KEY_FINGERPRINT?"; then
      abort_run "The slots were left as they are, so the YubiKey does not hold this key."
    fi
    replace="y"
  fi

  info "gpg asks for the master key passphrase and for the OpenPGP admin PIN."
  info "The factory admin PIN is 12345678."
  echo ""

  move_subkey_to_card "Signature" 1 "$SUBKEY_FPR_SIGN" "$CARD_FPR_SIGN" "$replace"
  move_subkey_to_card "Encryption" 2 "$SUBKEY_FPR_ENCR" "$CARD_FPR_ENCR" "$replace"
  move_subkey_to_card "Authentication" 3 "$SUBKEY_FPR_AUTH" "$CARD_FPR_AUTH" "$replace"

  # The card is asked what it holds, and the answer is compared with the
  # subkeys chosen above. An empty slot or another key stops the run here,
  # before any PIN is changed and long before an export is removed.
  echo ""
  info "Verifying keys are on the YubiKey..."
  until verify_card_slots; do
    echo ""
    error "The YubiKey does not hold all three subkeys."
    if ! prompt_yn "Open gpg --edit-key here to move the missing ones by hand?" "y"; then
      abort_run "The subkeys are not on the YubiKey."
    fi
    echo ""
    echo "  For each line, enter the key command, then keytocard, then the slot"
    echo "  number, then the same key command again to deselect the subkey."
    echo "  Leave out a slot the check above reported as holding its subkey."
    echo ""
    echo "    key $SUBKEY_FPR_SIGN    slot 1 (Signature key)"
    echo "    key $SUBKEY_FPR_ENCR    slot 2 (Encryption key)"
    echo "    key $SUBKEY_FPR_AUTH    slot 3 (Authentication key)"
    echo ""
    echo "  Finish with: save"
    echo ""
    gpg --edit-key "$KEY_FINGERPRINT" || true
    echo ""
    info "Verifying keys are on the YubiKey..."
  done
  success "All three subkeys are on the YubiKey."
}
# ANCHOR_END: keytocard

# Offer to change one credential, and record whether the change ran. The script
# cannot ask a token whether a PIN is still the factory one without spending a
# retry, so it goes by what happened in this run. A credential that was not
# changed here stops the run unless --allow-default-pins was given, which is
# the flag for a token whose PINs were set on an earlier day.
change_credential() {
  local label="$1"
  shift
  local failures=0
  while true; do
    if prompt_yn "Change the $label?" "y"; then
      release_card
      if "$@"; then
        success "$label changed."
        return 0
      fi
      error "The $label was not changed."
      failures=$((failures + 1))
      # A third wrong entry of the current value blocks the credential.
      if ((failures >= 2)); then
        abort_run "Two attempts to change the $label failed. A third wrong entry can block it, so the run stops here."
      fi
      continue
    fi
    if $OPT_ALLOW_DEFAULT_PINS; then
      warn "--allow-default-pins given: the $label stays as it was."
      UNCHANGED_CREDENTIALS+=("YubiKey $CURRENT_SERIAL: $label")
      return 0
    fi
    error "The $label was not changed in this run, and its factory value is public."
    if ! prompt_yn "Go back and change it?" "y"; then
      abort_run "Refusing to finish with a $label that was not changed. Pass --allow-default-pins if it was already set on this token."
    fi
  done
}

phase_pins() {
  header "Phase 4: YubiKey PIN Configuration"

  check_yubikey

  info "Factory values: OpenPGP user PIN 123456, admin PIN 12345678,"
  info "PIV PIN 123456, PIV PUK 12345678."
  echo ""

  if $DRY_RUN; then
    dry_run_skip "ykman openpgp access change-pin"
    dry_run_skip "ykman openpgp access change-admin-pin"
    dry_run_skip "ykman piv access change-pin"
    dry_run_skip "ykman piv access change-puk"
    dry_run_skip "ykman piv access change-management-key --generate --protect"
    info "Would prompt to change PINs and set cardholder name."
    return
  fi

  change_credential "OpenPGP user PIN" ykman openpgp access change-pin
  change_credential "OpenPGP admin PIN" ykman openpgp access change-admin-pin

  # The PIV applet is changed here, before Phase 6 writes an age identity
  # into it, so the identity is never guarded by the factory PIN. The
  # management key is replaced by a random one stored on the token behind the
  # PIN. age-plugin-yubikey accepts the factory key or a PIN-protected one and
  # refuses any other.
  change_credential "PIV PIN" ykman piv access change-pin
  change_credential "PIV PUK" ykman piv access change-puk
  change_credential "PIV management key" ykman piv access change-management-key --generate --protect

  if prompt_yn "Set cardholder name on the YubiKey?"; then
    local name
    name=$(prompt_required "Cardholder name")
    GNUPGHOME="$GNUPGHOME" gpg --command-fd=0 --edit-card <<EOF
admin
name
${name}

quit
EOF
    success "Cardholder name set."
  fi
}

phase_u2f() {
  header "Phase 5: U2F Registration"

  check_yubikey

  info "Generating U2F credential for PAM authentication."
  info "Touch your YubiKey when it blinks."
  echo ""

  local credential=""

  if $DRY_RUN; then
    dry_run_skip "pamu2fcfg -n -o $DEFAULT_U2F_ORIGIN"
    credential="DRY_RUN_U2F_CREDENTIAL"
    info "Would register a U2F credential for PAM."
    U2F_CREDENTIALS+=("$credential")
    return
  fi

  credential=$(pamu2fcfg -n -o "$DEFAULT_U2F_ORIGIN" 2>/dev/null) || {
    error "U2F registration failed. Make sure the FIDO2 applet is functional."
    warn "You can skip this and register later with: pamu2fcfg -n -o pam://yubi"
    U2F_CREDENTIALS+=("")
    return
  }

  if [[ -n $credential ]]; then
    success "U2F credential captured."
  else
    warn "U2F credential was empty. You may need to register manually later."
  fi
  U2F_CREDENTIALS+=("$credential")
}

phase_age() {
  header "Phase 6: age-plugin-yubikey Setup"

  check_yubikey

  info "Setting up age identity on YubiKey for sops-nix."
  info "This creates a new age key in a PIV slot on the YubiKey."
  echo ""

  local slot
  slot=$(prompt_value "PIV slot to use (1-4)" "1")

  local identity="" recipient="" full_output=""

  if $DRY_RUN; then
    dry_run_skip "age-plugin-yubikey --generate --slot $slot --name sops-nix --pin-policy once --touch-policy always"
    AGE_IDENTITIES+=("AGE-PLUGIN-YUBIKEY-DRY-RUN")
    AGE_RECIPIENTS+=("age1yubikey1qdryrun")
    AGE_FULL_OUTPUTS+=("# Dry run, no identity generated")
    info "Would generate age identity in PIV slot $slot."
    return
  fi

  info "Generating age identity (touch policy: always, PIN policy: once)..."
  echo ""

  # Only stdout is captured, which is where the plugin writes the identity.
  # Its PIN and touch prompts go to the terminal.
  release_card
  full_output=$(age-plugin-yubikey --generate \
    --slot "$slot" \
    --name "sops-nix" \
    --pin-policy once \
    --touch-policy always) || {
    error "age-plugin-yubikey generation failed."
    warn "You can retry manually: age-plugin-yubikey --generate"
    AGE_IDENTITIES+=("")
    AGE_RECIPIENTS+=("")
    AGE_FULL_OUTPUTS+=("")
    return
  }

  # Extract the identity line and recipient
  identity=$(echo "$full_output" | grep "^AGE-PLUGIN-YUBIKEY-" | head -n 1 || true)
  recipient=$(echo "$full_output" | grep -o "age1yubikey1[0-9a-z]*" | head -n 1 || true)

  if [[ -n $identity ]]; then
    success "age identity generated."
  else
    warn "Could not parse age identity from output."
    echo "$full_output"
  fi

  AGE_IDENTITIES+=("$identity")
  AGE_RECIPIENTS+=("$recipient")
  AGE_FULL_OUTPUTS+=("$full_output")
}

phase_ssh_keygrip() {
  header "Phase 7: SSH Keygrip Extraction"

  if $DRY_RUN; then
    SSH_KEYGRIP="DRY_RUN_KEYGRIP_0000000000000000"
    SSH_PUBKEY="ssh-ed25519 DRY_RUN_SSH_PUBKEY"
    dry_run_skip "gpg --list-keys --with-keygrip (extract [A] keygrip)"
    dry_run_skip "gpg --export-ssh-key"
    info "Would extract SSH keygrip and public key."
    return
  fi

  # Get keygrip of the authentication subkey
  local keygrip_output
  keygrip_output=$(GNUPGHOME="$GNUPGHOME" gpg --list-keys --with-keygrip "$KEY_FINGERPRINT" 2>/dev/null)

  # The auth subkey has [A] usage flag, so find its keygrip
  # Parse: look for line with [A] usage, then the next Keygrip line
  SSH_KEYGRIP=$(echo "$keygrip_output" |
    awk '/\[A\]/{found=1} found && /Keygrip/{print $3; exit}')

  if [[ -n $SSH_KEYGRIP ]]; then
    success "SSH keygrip: $SSH_KEYGRIP"
  else
    warn "Could not extract SSH keygrip automatically."
    echo "Key listing:"
    echo "$keygrip_output"
    SSH_KEYGRIP=$(prompt_value "Enter the authentication [A] keygrip manually" "")
  fi

  # Export SSH public key
  SSH_PUBKEY=$(GNUPGHOME="$GNUPGHOME" gpg --export-ssh-key "$KEY_FINGERPRINT" 2>/dev/null || true)

  if [[ -n $SSH_PUBKEY ]]; then
    success "SSH public key exported."
  fi
}

phase_import_pubkey() {
  header "Phase 8: Import Public Key to Persistent Keyring"

  if $DRY_RUN; then
    dry_run_skip "gpg --import public.key"
    dry_run_skip "gpg --edit-key trust (ultimate)"
    info "Would import public key into persistent ~/.gnupg keyring."
    return
  fi

  if [[ -z $BACKUP_DIR || ! -f "$BACKUP_DIR/public.key" ]]; then
    warn "No public key backup found. Exporting from temp keyring."
    # Into the temporary GNUPGHOME rather than a predictable /tmp path, so it
    # is torn down with everything else. Public material, but a stable name in
    # a shared directory is still a name anyone can guess and pre-create.
    local pubkey_file="$GNUPGHOME/public.key"
    GNUPGHOME="$GNUPGHOME" gpg --armor --export "$KEY_FINGERPRINT" >"$pubkey_file"
  else
    local pubkey_file="$BACKUP_DIR/public.key"
  fi

  info "Importing public key into your persistent keyring (~/.gnupg)..."

  # Temporarily unset GNUPGHOME to use the real one
  local saved_gnupghome="$GNUPGHOME"
  unset GNUPGHOME

  gpg --import "$pubkey_file" 2>/dev/null || {
    warn "Import may have failed or key already exists."
  }

  # Set ultimate trust
  echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "$KEY_FINGERPRINT" trust 2>/dev/null || {
    warn "Could not set trust automatically. Run: gpg --edit-key $KEY_FINGERPRINT trust"
  }

  # Verify card status with real keyring
  if gpg --card-status &>/dev/null; then
    success "Card detected with persistent keyring."
  else
    warn "Card status check failed. You may need to run: gpg --card-status"
  fi

  # Restore temp GNUPGHOME for remaining operations
  export GNUPGHOME="$saved_gnupghome"
}

# ANCHOR: age-backup
# Encrypt the plaintext exports, verify the results, and remove the plaintext.
#
# This runs after every YubiKey is provisioned rather than inside phase_backup,
# and the ordering is forced rather than chosen. The backup has to exist before
# `keytocard` in Phase 3, since that move is irreversible, and the plaintext has
# to survive the provisioning loop because subkeys are re-imported from it
# between each key. The age recipients do not exist until Phase 6 has run for a
# token. Encrypting earlier is therefore impossible in both directions.
#
# Two files for each export, because `age` refuses -p together with -r. The
# token copy is encrypted to the age recipients this run provisioned plus
# anything given with --age-recipient. The passphrase copy exists so that losing
# every token does not lose the identity, which is the exact case the master key
# backup is for.
BACKUP_RECIPIENTS=()
BACKUP_IDFILE=""

# One export through the whole sequence. $1 is the plaintext, which sits in the
# backup directory on a first run and in the ramfs after an encrypted import.
# $2 is the path in the backup directory the encrypted copies are named after.
#
# Each copy is written as <name>.new, decrypted, compared byte for byte with the
# plaintext, and only then moved into place, so a copy from an earlier run is
# never replaced by one that has not been opened.
protect_export() {
  local plaintext="$1" dest="$2"
  local name enc="$2.age" pass_enc="$2.pass.age"
  local check="$GNUPGHOME/verify.tmp"
  local token_ok=false pass_ok=false on_medium=false
  name=$(basename "$dest")
  in_gnupghome "$plaintext" || on_medium=true

  if [[ ${#BACKUP_RECIPIENTS[@]} -gt 0 ]]; then
    local -a args=()
    local r
    for r in "${BACKUP_RECIPIENTS[@]}"; do args+=(-r "$r"); done
    info "Encrypting $name to ${#BACKUP_RECIPIENTS[@]} age recipient(s)..."
    if age "${args[@]}" -o "$enc.new" "$plaintext"; then
      # Decrypting a YubiKey recipient needs the token in the reader, its PIN
      # and a touch, so this proves the file opens with hardware rather than
      # only that age wrote something. It can only test the token currently
      # inserted, which after a multi-key run is the last one provisioned.
      info "Verifying $enc (this needs the inserted YubiKey's PIN and a touch)..."
      if [[ -s $BACKUP_IDFILE ]] &&
        age -d -i "$BACKUP_IDFILE" -o "$check" "$enc.new" &&
        cmp -s "$plaintext" "$check"; then
        mv -f "$enc.new" "$enc"
        token_ok=true
        success "Token-encrypted backup verified: $enc"
      elif [[ -e $enc ]]; then
        warn "Could not verify the new token-encrypted copy of $name."
        warn "$enc from an earlier run was kept. The new copy is $enc.new."
      else
        mv -f "$enc.new" "$enc"
        warn "Could not verify $enc against the inserted token."
        warn "The file was written, but nothing here has proved it opens."
      fi
      rm -f "$check"
    else
      error "Encrypting $name to age recipients failed."
      rm -f "$enc.new"
    fi
  else
    warn "No age recipients captured, so no token-encrypted copy of $name was made."
  fi

  if ! $OPT_NO_AGE_PASSPHRASE; then
    echo ""
    info "Now a passphrase-encrypted copy of $name, so losing every YubiKey does"
    info "not lose the identity. Use a passphrase you can recover without this host."
    if age -p -o "$pass_enc.new" "$plaintext"; then
      info "Verifying $pass_enc (re-enter the same passphrase)..."
      if age -d -o "$check" "$pass_enc.new" &&
        cmp -s "$plaintext" "$check"; then
        mv -f "$pass_enc.new" "$pass_enc"
        pass_ok=true
        success "Passphrase-encrypted backup verified: $pass_enc"
      else
        error "Could not verify the passphrase-encrypted copy of $name."
        rm -f "$pass_enc.new"
      fi
      rm -f "$check"
    else
      error "Passphrase encryption failed or was cancelled."
      rm -f "$pass_enc.new"
    fi
  fi

  # The plaintext goes only against a copy that has been decrypted and compared
  # byte for byte in this run. Removing the only copy of a key on the strength
  # of a write that returned zero is the one mistake this must not make, so an
  # unverified encrypt keeps the plaintext and says why.
  if $pass_ok || $token_ok; then
    if $OPT_KEEP_PLAINTEXT && $on_medium; then
      warn "--keep-plaintext given: $plaintext left in place."
      warn "It is unencrypted key material. Store it accordingly."
      return 0
    fi
    remove_plaintext "$plaintext"
    success "Plaintext $name removed; encrypted copies remain."
    # A plaintext file of the same name that an earlier run left behind. It
    # goes only when every key in it is in the export just encrypted.
    if [[ $dest != "$plaintext" && -e $dest ]]; then
      if ! $OPT_KEEP_PLAINTEXT && export_is_covered "$dest"; then
        remove_plaintext "$dest"
        info "Removed $dest from an earlier run. The new encrypted copy holds every key in it."
      else
        PLAINTEXT_LEFT+=("$dest")
      fi
    fi
    if ! $pass_ok; then
      warn "Only the token-encrypted copy of $name verified. Losing every YubiKey"
      warn "now means losing it. Consider re-running with a passphrase copy."
    fi
    return 0
  fi

  if $on_medium; then
    warn "No encrypted copy verified, so $plaintext was left in place."
    warn "Do not delete it until you have a copy you have opened."
    PLAINTEXT_LEFT+=("$plaintext")
    return 0
  fi

  # The plaintext is in the ramfs and goes when the script exits. Without a
  # verified copy, anything generated in this run would exist nowhere else.
  error "No encrypted copy of $name verified, and the plaintext is held in memory only."
  if prompt_yn "Write it to $dest unencrypted so it is not lost?" "y"; then
    if cp "$plaintext" "$dest.new" && cmp -s "$plaintext" "$dest.new"; then
      mv -f "$dest.new" "$dest"
      PLAINTEXT_LEFT+=("$dest")
    else
      rm -f "$dest.new"
      error "Could not write $dest."
    fi
  else
    warn "$name was not saved. The backup in $BACKUP_DIR is as it was before this run."
  fi
  return 0
}

phase_age_backup() {
  [[ -n $BACKUP_DIR && -n $MASTER_PLAINTEXT ]] || return 0

  local master_dest="$BACKUP_DIR/master-secret.key"
  local subkeys_dest="$BACKUP_DIR/subkeys-secret.key"

  if $OPT_NO_AGE_BACKUP; then
    if in_gnupghome "$MASTER_PLAINTEXT"; then
      warn "--no-age-backup given: the backup in $BACKUP_DIR was not updated."
      warn "Subkeys generated in this run exist only on the YubiKeys."
    fi
    return 0
  fi

  if $DRY_RUN; then
    header "Encrypted Key Backup"
    dry_run_skip "age -r <recipients> -o $master_dest.age.new, verify, mv to $master_dest.age"
    dry_run_skip "age -p -o $master_dest.pass.age.new, verify, mv to $master_dest.pass.age"
    dry_run_skip "the same two copies of $subkeys_dest"
    dry_run_skip "shred the plaintext exports once a copy of each has verified"
    return 0
  fi

  [[ -f $MASTER_PLAINTEXT ]] || return 0

  header "Encrypted Key Backup"

  # Recipients: the tokens provisioned in this run, plus anything supplied.
  local r
  BACKUP_RECIPIENTS=()
  for r in "${AGE_RECIPIENTS[@]}"; do
    [[ -n $r ]] && BACKUP_RECIPIENTS+=("$r")
  done
  for r in "${OPT_AGE_RECIPIENTS[@]+"${OPT_AGE_RECIPIENTS[@]}"}"; do
    [[ -n $r ]] && BACKUP_RECIPIENTS+=("$r")
  done

  # A real file rather than process substitution, since age reads the identity
  # file directly and /dev/fd paths are not seekable. It lives in the ramfs
  # GNUPGHOME and goes with it.
  BACKUP_IDFILE="$GNUPGHOME/age-identities"
  : >"$BACKUP_IDFILE"
  for r in "${AGE_IDENTITIES[@]}"; do
    [[ -n $r ]] && printf '%s\n' "$r" >>"$BACKUP_IDFILE"
  done

  if [[ -e $master_dest.age && ${#BACKUP_RECIPIENTS[@]} -gt 0 ]]; then
    warn "$master_dest.age exists and is replaced once the new copy verifies."
    warn "The new copy opens with the YubiKeys provisioned in this run and with"
    warn "any --age-recipient. Recipients of the old copy are not carried over."
  fi
  if ! $OPT_NO_AGE_PASSPHRASE; then
    info "age asks for the passphrase twice to encrypt each export and once to"
    info "verify it. Use the same passphrase for both exports."
  fi

  protect_export "$MASTER_PLAINTEXT" "$master_dest"
  if [[ -n $SUBKEYS_PLAINTEXT && -f $SUBKEYS_PLAINTEXT ]]; then
    echo ""
    protect_export "$SUBKEYS_PLAINTEXT" "$subkeys_dest"
  fi

  # The plaintext file a rotation started from, when it was not the file the
  # new export replaced. It goes on the same terms as any older plaintext.
  if [[ -n $IMPORTED_PLAINTEXT && -e $IMPORTED_PLAINTEXT ]] && ! $OPT_KEEP_PLAINTEXT; then
    if [[ ! -e $MASTER_PLAINTEXT ]] && export_is_covered "$IMPORTED_PLAINTEXT"; then
      remove_plaintext "$IMPORTED_PLAINTEXT"
      info "Removed $IMPORTED_PLAINTEXT. The new encrypted copy holds every key in it."
    else
      PLAINTEXT_LEFT+=("$IMPORTED_PLAINTEXT")
    fi
  fi

  rm -f "$BACKUP_IDFILE"
}
# ANCHOR_END: age-backup

phase_summary() {
  header "YubiKey Onboarding Complete"

  local short_fp="${KEY_FINGERPRINT: -16}"
  local i

  echo -e "${BOLD}GPG Fingerprint:${NC} $KEY_FINGERPRINT"
  echo -e "${BOLD}YubiKeys provisioned:${NC} $NUM_KEYS"
  for ((i = 0; i < NUM_KEYS; i++)); do
    echo "  Key #$((i + 1)): serial ${YUBIKEY_SERIALS[$i]}"
  done
  echo ""

  echo -e "${CYAN}--- Values for your host configurations ---${NC}"
  echo ""

  # SSH Keygrips (same for all keys, since it is the same GPG key)
  echo -e "${BOLD}# othrys.services.security.yubikey.sshKeygrips${NC}"
  echo "sshKeygrips = [\"$SSH_KEYGRIP\"];"
  echo ""

  # U2F Mappings (one credential per YubiKey)
  echo -e "${BOLD}# othrys.services.security.yubikey.u2fMappings.\${username}${NC}"
  local has_u2f=false
  for ((i = 0; i < NUM_KEYS; i++)); do
    if [[ -n ${U2F_CREDENTIALS[$i]} ]]; then
      has_u2f=true
      break
    fi
  done
  if $has_u2f; then
    # shellcheck disable=SC2016 # printing literal Nix ${username}, not expanding
    echo 'u2fMappings.${username} = ['
    for ((i = 0; i < NUM_KEYS; i++)); do
      if [[ -n ${U2F_CREDENTIALS[$i]} ]]; then
        echo "  # YubiKey #$((i + 1)) (serial ${YUBIKEY_SERIALS[$i]})"
        echo "  \"${U2F_CREDENTIALS[$i]}\""
      fi
    done
    echo "];"
  else
    echo "# (no U2F credentials captured, register manually with pamu2fcfg)"
  fi
  echo ""

  # Age identity stub (one per YubiKey, using the primary key's identity for
  # sops-nix). The YubiKey plugin stub carries no key material, so it is safe
  # in the store, unlike a raw AGE-SECRET-KEY.
  echo -e "${BOLD}# othrys.system.secrets.ageIdentityStubs (primary YubiKey)${NC}"
  if [[ -n ${AGE_FULL_OUTPUTS[0]} ]]; then
    echo "ageIdentityStubs = ''"
    echo "${AGE_FULL_OUTPUTS[0]}" | grep "^#" | sed 's/^/  /'
    echo "  ${AGE_IDENTITIES[0]}"
    echo "'';"
  else
    echo "# (age identity was not captured, generate with age-plugin-yubikey)"
  fi
  echo ""

  # Git signing key
  echo -e "${BOLD}# Git signing key (add to git config or modules/system/git.nix)${NC}"
  echo "signing.key = \"0x$short_fp\";"
  echo ""

  # SSH public key
  echo -e "${BOLD}# SSH public key (for GitHub, servers, authorized_keys)${NC}"
  if [[ -n $SSH_PUBKEY ]]; then
    echo "$SSH_PUBKEY"
  else
    echo "# (not captured, export with gpg --export-ssh-key $KEY_FINGERPRINT)"
  fi
  echo ""

  # Age recipients (all keys, add all to .sops.yaml for redundancy)
  echo -e "${BOLD}# age recipients (for .sops.yaml in secrets repo)${NC}"
  for ((i = 0; i < NUM_KEYS; i++)); do
    if [[ -n ${AGE_RECIPIENTS[$i]} ]]; then
      echo "# YubiKey #$((i + 1)) (serial ${YUBIKEY_SERIALS[$i]})"
      echo "${AGE_RECIPIENTS[$i]}"
    fi
  done
  echo ""

  echo -e "${CYAN}--- Manual Steps Remaining ---${NC}"
  echo ""
  echo "  1. Update your fleet's host configurations with the above values"
  echo "  2. Update .sops.yaml in the secrets repo with ALL age recipients above"
  echo "  3. Re-encrypt secrets: sops updatekeys <secret-files>"
  echo "  4. Upload public key to GitHub: gpg --armor --export $KEY_FINGERPRINT"
  echo "  5. Rebuild: just switch <hostname>"
  echo ""

  # Write summary to a file for reference.
  #
  # Beside the backup rather than in /tmp. It carries the keygrip, the age
  # recipients and the U2F credential lines, all of which the operator needs
  # later to fill in host configuration, and none of which survives a reboot in
  # a temp directory. It never goes to the working directory, which may be a
  # public checkout. When the backup directory is gone, as when the medium was
  # unmounted during the run, it goes to a private directory the script creates.
  local summary_file summary_dir fallback_base="${XDG_RUNTIME_DIR:-}"
  if [[ -z $fallback_base || ! -d $fallback_base || ! -w $fallback_base ]]; then
    fallback_base="/tmp"
  fi

  # A dry run writes nothing, and says where a real run would write.
  if $DRY_RUN; then
    dry_run_skip "writing the summary file"
    if [[ -n $BACKUP_DIR ]]; then
      info "Summary would be saved under: $BACKUP_DIR"
    else
      info "Summary would be saved under: $fallback_base/yubikey-onboard-XXXXXXXX"
    fi
    return 0
  fi

  if [[ -n $BACKUP_DIR && -d $BACKUP_DIR ]]; then
    summary_dir="$BACKUP_DIR"
  else
    summary_dir=$(mktemp -d "$fallback_base/yubikey-onboard-XXXXXXXX")
    chmod 700 "$summary_dir"
    warn "The backup directory is not available, so the summary goes to a"
    warn "private directory that does not survive a reboot. Copy it from there."
  fi
  summary_file="$summary_dir/yubikey-onboard-summary-$(date +%Y%m%d-%H%M%S).txt"
  {
    echo "YubiKey Onboarding Summary, $(date)"
    echo "Fingerprint: $KEY_FINGERPRINT"
    echo "SSH Keygrip: $SSH_KEYGRIP"
    echo "SSH Public Key: $SSH_PUBKEY"
    echo "Keys provisioned: $NUM_KEYS"
    for ((i = 0; i < NUM_KEYS; i++)); do
      echo ""
      echo "--- YubiKey #$((i + 1)) (serial ${YUBIKEY_SERIALS[$i]}) ---"
      echo "U2F Credential: ${U2F_CREDENTIALS[$i]}"
      echo "age Identity: ${AGE_IDENTITIES[$i]}"
      echo "age Recipient: ${AGE_RECIPIENTS[$i]}"
    done
  } >"$summary_file"

  info "Summary saved to: $summary_file"
}

# ANCHOR: from-backup
# What a backup file is. age opens a file with a text header whose second line
# names the first recipient stanza, and `scrypt` there means a passphrase.
backup_form() {
  local file="$1" first="" second=""
  {
    IFS= read -r first || true
    IFS= read -r second || true
  } <"$file" 2>/dev/null
  if [[ $first == "age-encryption.org/v1" || $file == *.age ]]; then
    if [[ $second == "-> scrypt "* || $file == *.pass.age ]]; then
      echo "age-passphrase"
    else
      echo "age-recipient"
    fi
  else
    echo "plaintext"
  fi
}

# Decrypt an encrypted backup to a file inside the ramfs GNUPGHOME. The
# passphrase copy needs nothing but the passphrase. The token copy needs an
# identity, which is a file named with --age-identity or at the prompt, or the
# YubiKey in the reader through age-plugin-yubikey.
decrypt_backup() {
  local source="$1" form="$2" dest="$3"
  local idfile="$OPT_AGE_IDENTITY" rc=0

  if [[ $form == "age-passphrase" ]]; then
    info "Decrypting $source. age asks for the backup passphrase."
    age -d -o "$dest" "$source"
    return
  fi

  if [[ -z $idfile ]]; then
    idfile=$(prompt_value "age identity file that opens it (empty to use the YubiKey in the reader)" "")
  fi
  if [[ -n $idfile ]]; then
    if [[ ! -f $idfile ]]; then
      error "No such identity file: $idfile"
      return 1
    fi
    age -d -i "$idfile" -o "$dest" "$source"
    return
  fi

  idfile="$GNUPGHOME/age-identities"
  release_card
  age-plugin-yubikey --identity >"$idfile" 2>/dev/null || true
  if ! grep -q "^AGE-PLUGIN-YUBIKEY-" "$idfile"; then
    rm -f "$idfile"
    error "The YubiKey in the reader holds no age identity."
    return 1
  fi
  info "Decrypting $source (this needs the inserted YubiKey's PIN and a touch)..."
  age -d -i "$idfile" -o "$dest" "$source" || rc=$?
  rm -f "$idfile"
  return "$rc"
}

phase_import_from_backup() {
  header "Importing Master Key from Backup"

  local backup_path="$OPT_FROM_BACKUP"

  # Validate backup path
  if [[ ! -f $backup_path && ! -d $backup_path ]]; then
    error "Backup path does not exist: $backup_path"
    exit 1
  fi

  # If a directory was given, look for the master key file inside it. A
  # plaintext export comes first because it needs nothing to open. A default
  # run leaves only the two encrypted copies.
  local key_file="$backup_path"
  if [[ -d $backup_path ]]; then
    if [[ -f "$backup_path/master-secret.key" ]]; then
      key_file="$backup_path/master-secret.key"
    elif [[ -f "$backup_path/master-secret.key.pass.age" && -f "$backup_path/master-secret.key.age" ]]; then
      if prompt_yn "Open the passphrase copy? Answer no to open the YubiKey copy." "y"; then
        key_file="$backup_path/master-secret.key.pass.age"
      else
        key_file="$backup_path/master-secret.key.age"
      fi
    elif [[ -f "$backup_path/master-secret.key.pass.age" ]]; then
      key_file="$backup_path/master-secret.key.pass.age"
    elif [[ -f "$backup_path/master-secret.key.age" ]]; then
      key_file="$backup_path/master-secret.key.age"
    else
      error "No master-secret.key, master-secret.key.age or master-secret.key.pass.age in $backup_path"
      error "Expected a file produced by a previous onboarding run."
      exit 1
    fi
    # The directory takes the updated backup and the summary.
    BACKUP_DIR="$backup_path"
  else
    BACKUP_DIR="$(dirname "$backup_path")"
  fi

  local form
  form=$(backup_form "$key_file")

  info "Importing master key from: $key_file"

  setup_gnupghome

  # An encrypted backup is decrypted into the ramfs, and every plaintext export
  # of this run stays there. A plaintext backup is already on the medium, so its
  # exports stay beside it until the encrypted backup phase removes them.
  local source="$key_file"
  if [[ $form == "plaintext" ]]; then
    MASTER_PLAINTEXT="$BACKUP_DIR/master-secret.key"
    SUBKEYS_PLAINTEXT="$BACKUP_DIR/subkeys-secret.key"
  else
    MASTER_PLAINTEXT="$GNUPGHOME/master-secret.key"
    SUBKEYS_PLAINTEXT="$GNUPGHOME/subkeys-secret.key"
    key_file="$MASTER_PLAINTEXT"
  fi

  if $DRY_RUN; then
    if [[ $form != "plaintext" ]]; then
      dry_run_skip "age -d $source (into the ramfs)"
    fi
    dry_run_skip "gpg --import $key_file"
    KEY_FINGERPRINT="DRY_RUN_FINGERPRINT_0000000000000000"
    info "Would import master key and list existing subkeys."
    return
  fi

  if [[ $form == "plaintext" ]]; then
    warn "$source is not encrypted. It stays on the medium until the encrypted"
    warn "backup phase at the end of this run."
  else
    if ! decrypt_backup "$source" "$form" "$key_file" || [[ ! -s $key_file ]]; then
      error "Could not decrypt $source. Nothing was changed."
      exit 1
    fi
    success "Backup decrypted into the temporary GNUPGHOME."
    if [[ $form == "age-recipient" ]]; then
      info "If the YubiKey to provision is not the one in the reader, insert it now."
      read -rp "$(echo -e "${BOLD}Press Enter to continue...${NC}")" || true
    fi
  fi

  # Import the master key
  gpg --batch --import "$key_file" 2>/dev/null || {
    error "Failed to import master key from $key_file"
    exit 1
  }

  # Get the fingerprint (first key in the keyring)
  KEY_FINGERPRINT=$(gpg --list-keys --with-colons 2>/dev/null |
    awk -F: '/^fpr:/ {print $10; exit}')

  if [[ -z $KEY_FINGERPRINT ]]; then
    error "Failed to retrieve key fingerprint after import."
    exit 1
  fi

  success "Master key imported: $KEY_FINGERPRINT"
  echo ""
  gpg --list-keys --with-keygrip "$KEY_FINGERPRINT"

  # Check if subkeys exist and offer to generate new ones
  local subkey_count regenerated=false
  subkey_count=$(gpg --list-keys --with-colons "$KEY_FINGERPRINT" 2>/dev/null |
    grep -c "^sub:" || true)

  if [[ $subkey_count -ge 3 ]]; then
    info "Found $subkey_count existing subkeys."
    if prompt_yn "Generate fresh subkeys (recommended for rotation)?" "y"; then
      local expiry
      if [[ -n $OPT_EXPIRY ]]; then
        expiry="$OPT_EXPIRY"
      else
        expiry=$(prompt_value "New subkey expiry (e.g., 2y, 1y, 6m)" "$DEFAULT_EXPIRY")
      fi

      info "Generating new subkeys with expiry: $expiry..."
      if [[ $KEY_ALGO == "ed25519" ]]; then
        gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" ed25519 sign "$expiry"
        gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" cv25519 encr "$expiry"
        gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" ed25519 auth "$expiry"
      else
        gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 sign "$expiry"
        gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 encr "$expiry"
        gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 auth "$expiry"
      fi
      success "New subkeys generated."
      regenerated=true
      echo ""
      gpg --list-keys --with-keygrip "$KEY_FINGERPRINT"
    else
      info "Using existing subkeys from backup."
    fi
  elif [[ $subkey_count -eq 0 ]]; then
    warn "No subkeys found in backup. Generating new subkeys..."
    local expiry
    if [[ -n $OPT_EXPIRY ]]; then
      expiry="$OPT_EXPIRY"
    else
      expiry=$(prompt_value "Subkey expiry (e.g., 2y, 1y, 6m)" "$DEFAULT_EXPIRY")
    fi

    if [[ $KEY_ALGO == "ed25519" ]]; then
      gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" ed25519 sign "$expiry"
      gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" cv25519 encr "$expiry"
      gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" ed25519 auth "$expiry"
    else
      gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 sign "$expiry"
      gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 encr "$expiry"
      gpg --batch --passphrase '' --quick-add-key "$KEY_FINGERPRINT" rsa4096 auth "$expiry"
    fi
    success "Subkeys generated."
    regenerated=true
    echo ""
    gpg --list-keys --with-keygrip "$KEY_FINGERPRINT"
  else
    info "Found $subkey_count subkey(s). Proceeding with existing subkeys."
  fi

  if $regenerated; then
    # The key has changed, so the exports follow it. Each is written beside its
    # target as <target>.new and moved into place after it has been read back,
    # so a failed export leaves the existing backup as it was.
    export_verified master "$MASTER_PLAINTEXT" || abort_run "The updated master key could not be exported."
    export_verified subkeys "$SUBKEYS_PLAINTEXT" || abort_run "The updated subkeys could not be exported."
    export_verified public "$BACKUP_DIR/public.key" || abort_run "The updated public key could not be exported."
    if [[ $form == "plaintext" && $source != "$MASTER_PLAINTEXT" ]]; then
      IMPORTED_PLAINTEXT="$source"
    fi
  else
    # Nothing changed, so the imported file is the export and is not rewritten.
    MASTER_PLAINTEXT="$key_file"
    # A plaintext subkeys export from an earlier run is taken through the
    # encrypted backup phase too, provided it belongs to this key.
    if [[ -f "$BACKUP_DIR/subkeys-secret.key" ]] && export_is_covered "$BACKUP_DIR/subkeys-secret.key"; then
      SUBKEYS_PLAINTEXT="$BACKUP_DIR/subkeys-secret.key"
    else
      SUBKEYS_PLAINTEXT=""
    fi
  fi
}
# ANCHOR_END: from-backup

# ANCHOR: verify
mode_verify() {
  header "YubiKey Verification"

  # Check tools
  local tools=("gpg" "ykman" "age-plugin-yubikey")
  local missing=()
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      missing+=("$tool")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing tools: ${missing[*]}"
    exit 1
  fi

  # YubiKey detection
  if ! ykman info &>/dev/null; then
    error "No YubiKey detected."
    exit 1
  fi

  local serial firmware
  serial=$(yubikey_info_field "Serial number")
  firmware=$(yubikey_info_field "Firmware version")
  success "YubiKey detected (serial: ${serial:-$NO_SERIAL}, firmware: ${firmware:-unreported})"

  # OpenPGP card status
  echo ""
  info "OpenPGP card status:"
  local card_status
  card_status=$(gpg --card-status 2>/dev/null || true)

  if [[ -z $card_status ]]; then
    warn "  Could not read OpenPGP card status."
  else
    local sig_key enc_key auth_key
    sig_key=$(echo "$card_status" | grep "Signature key" | head -1 || true)
    enc_key=$(echo "$card_status" | grep "Encryption key" | head -1 || true)
    auth_key=$(echo "$card_status" | grep "Authentication key" | head -1 || true)

    if echo "$sig_key" | grep -q "none"; then
      warn "  Signature slot: empty"
    else
      success "  Signature slot: populated"
    fi
    if echo "$enc_key" | grep -q "none"; then
      warn "  Encryption slot: empty"
    else
      success "  Encryption slot: populated"
    fi
    if echo "$auth_key" | grep -q "none"; then
      warn "  Authentication slot: empty"
    else
      success "  Authentication slot: populated"
    fi
  fi

  # FIDO2/U2F status
  echo ""
  info "FIDO2 status:"
  local fido_info
  fido_info=$(ykman fido info 2>/dev/null || true)
  if [[ -n $fido_info ]]; then
    success "  FIDO2 applet accessible"
  else
    warn "  FIDO2 applet not accessible"
  fi

  # PIV/age status
  echo ""
  info "PIV slots (age-plugin-yubikey):"
  local age_identities
  age_identities=$(age-plugin-yubikey --identity 2>/dev/null || true)
  if [[ -n $age_identities ]]; then
    local slot_count
    slot_count=$(echo "$age_identities" | grep -c "^AGE-PLUGIN-YUBIKEY-" || true)
    success "  $slot_count age identity/identities found"
    echo "$age_identities" | grep "^#" | sed 's/^/    /'
  else
    warn "  No age identities found on this YubiKey"
  fi

  # GPG agent SSH
  echo ""
  info "GPG-agent SSH support:"
  local ssh_keys
  ssh_keys=$(ssh-add -L 2>/dev/null || true)
  if echo "$ssh_keys" | grep -q "cardno:"; then
    success "  SSH key from YubiKey available via gpg-agent"
  else
    warn "  No YubiKey SSH key in agent (may need: gpg --card-status)"
  fi

  # Check against NixOS config (best-effort)
  echo ""
  info "Config cross-reference:"
  local config_files=(hosts/*/default.nix)
  # An empty pattern matches every line, so a token without a serial would be
  # reported as found in every file.
  if [[ -z $serial ]]; then
    warn "  This token reports no serial number, so there is nothing to look up."
    config_files=()
  fi
  for cfg in "${config_files[@]+"${config_files[@]}"}"; do
    if [[ -f $cfg ]]; then
      if grep -qF -- "$serial" "$cfg" 2>/dev/null; then
        success "  Serial $serial found in $cfg"
      else
        warn "  Serial $serial NOT found in $cfg"
      fi
    fi
  done

  echo ""
  success "Verification complete."
}
# ANCHOR_END: verify

# Provision a single YubiKey: reset, keytocard, PINs, U2F, age.
# Called once per YubiKey in the provisioning loop.
provision_yubikey() {
  local key_num="$1"

  header "Provisioning YubiKey #$((key_num + 1))"

  detect_and_reset_yubikey "$key_num"
  phase_keytocard
  phase_pins
  phase_u2f
  phase_age
}

# ANCHOR: main
main() {
  # Handle --verify mode separately
  if $VERIFY_MODE; then
    mode_verify
    exit 0
  fi

  header "YubiKey Onboarding Script"
  echo "This script will guide you through provisioning a new YubiKey for use"
  echo "with this NixOS configuration (PGP, U2F, SSH, sops-nix)."
  echo ""
  echo "Following drduh's YubiKey guide: https://github.com/drduh/YubiKey-Guide"
  echo ""

  if $DRY_RUN; then
    warn "DRY-RUN MODE: No destructive operations will be performed."
    echo ""
  fi

  if [[ -n $OPT_FROM_BACKUP ]]; then
    info "Mode: key rotation (importing from existing backup)"
  else
    info "Mode: new key generation"
  fi
  echo ""

  if ! prompt_yn "Ready to begin?" "y"; then
    echo "Aborted."
    exit 0
  fi

  # gpg-agent starts pinentry on the terminal named here. Without it, a gpg
  # that is fed its commands on another descriptor has no terminal to name.
  if [[ -t 0 ]]; then
    GPG_TTY=$(tty)
    export GPG_TTY
  fi

  # One-time phases: preflight always runs
  phase_preflight

  # Either generate new keys or import from backup
  if [[ -n $OPT_FROM_BACKUP ]]; then
    phase_import_from_backup
  else
    phase_generate_keys
    phase_backup
  fi

  # Determine how many YubiKeys to provision
  local target_count="${OPT_KEY_COUNT:-}"

  # Provision first YubiKey
  provision_yubikey 0
  NUM_KEYS=1

  # Provision additional YubiKeys
  if [[ -n $target_count ]]; then
    # Non-interactive: provision exactly the requested count
    while [[ $NUM_KEYS -lt $target_count ]]; do
      echo ""
      info "Restoring subkeys so they can be moved to the next YubiKey..."
      restore_subkeys
      echo ""
      warn "Remove the current YubiKey and insert YubiKey #$((NUM_KEYS + 1))."
      read -rp "$(echo -e "${BOLD}Press Enter when the new YubiKey is inserted...${NC}")"
      echo ""

      provision_yubikey "$NUM_KEYS"
      NUM_KEYS=$((NUM_KEYS + 1))
    done
  else
    # Interactive: ask after each key
    while prompt_yn "Provision another YubiKey with the same PGP key (redundancy)?"; do
      echo ""
      info "Restoring subkeys so they can be moved to the next YubiKey..."
      restore_subkeys
      echo ""
      warn "Remove the current YubiKey and insert the next one."
      read -rp "$(echo -e "${BOLD}Press Enter when the new YubiKey is inserted...${NC}")"
      echo ""

      provision_yubikey "$NUM_KEYS"
      NUM_KEYS=$((NUM_KEYS + 1))
    done
  fi

  # One-time post-provisioning phases
  phase_ssh_keygrip
  phase_import_pubkey
  phase_age_backup
  phase_summary

  local item
  if [[ ${#UNCHANGED_CREDENTIALS[@]} -gt 0 ]]; then
    warn "Not changed in this run, as --allow-default-pins permits:"
    for item in "${UNCHANGED_CREDENTIALS[@]}"; do
      warn "  $item"
    done
  fi

  # Provisioning is done at this point, but a run that leaves key material
  # unencrypted on the backup medium does not end as a success.
  if [[ ${#PLAINTEXT_LEFT[@]} -gt 0 ]]; then
    error "$NUM_KEYS YubiKey(s) provisioned, but these exports are still plaintext:"
    for item in "${PLAINTEXT_LEFT[@]}"; do
      error "  $item"
    done
    error "Encrypt them or remove them. Each holds secret key material."
    exit 1
  fi

  if $DRY_RUN; then
    success "Dry run complete. Nothing was provisioned and nothing was written."
    return 0
  fi

  success "All done! $NUM_KEYS YubiKey(s) provisioned."
  success "Remember to clean up backup files from insecure locations."
}

# ANCHOR_END: main
main "$@"
