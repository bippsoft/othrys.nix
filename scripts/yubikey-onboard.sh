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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Minimum YubiKey firmware for ed25519 support
MIN_ECC_FIRMWARE="5.2.3"

# Defaults
DEFAULT_NAME="alice"
DEFAULT_EMAIL="alice@example.com"
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

# State, populated during execution
TEMP_GNUPGHOME=""
KEY_FINGERPRINT=""
SSH_KEYGRIP=""
SSH_PUBKEY=""
BACKUP_DIR=""
KEY_ALGO="ed25519"

# Per-YubiKey state (indexed by key number)
YUBIKEY_SERIALS=()
U2F_CREDENTIALS=()
AGE_IDENTITIES=()
AGE_RECIPIENTS=()
AGE_FULL_OUTPUTS=()
NUM_KEYS=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Provision one or more YubiKeys with PGP keys, U2F credentials, and age identity.

Modes:
  (default)            Generate new PGP keys and provision YubiKey(s)
  --from-backup <path> Import an existing master key backup and provision YubiKey(s)
                       (for key rotation or replacement YubiKeys)
  --verify             Check the currently inserted YubiKey's health and config

Key identity (skip interactive prompts):
  --name <name>        Real name for the PGP key (default: $DEFAULT_NAME)
  --email <email>      Email address for the PGP key (default: $DEFAULT_EMAIL)
  --expiry <duration>  Subkey expiry period (default: $DEFAULT_EXPIRY)

Provisioning options:
  --backup-dir <path>  Master key backup directory (skips the prompt)
  --algo <algorithm>   Force key algorithm: ed25519 or rsa4096 (auto-detected by default)
  --key-count <n>      Number of YubiKeys to provision (skips the "provision another?" prompt)
  --dry-run            Walk through all phases without destructive operations

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
    OPT_FROM_BACKUP="$2"
    shift 2
    ;;
  --backup-dir)
    OPT_BACKUP_DIR="$2"
    shift 2
    ;;
  --name)
    OPT_NAME="$2"
    shift 2
    ;;
  --email)
    OPT_EMAIL="$2"
    shift 2
    ;;
  --expiry)
    OPT_EXPIRY="$2"
    shift 2
    ;;
  --algo)
    OPT_ALGO="$2"
    if [[ $OPT_ALGO != "ed25519" && $OPT_ALGO != "rsa4096" ]]; then
      error "Invalid algorithm: $OPT_ALGO (must be ed25519 or rsa4096)"
      exit 1
    fi
    shift 2
    ;;
  --key-count)
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
    usage
    ;;
  esac
done

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

prompt_value() {
  local question="$1"
  local default="$2"
  local result
  read -rp "$(echo -e "${BOLD}$question${NC} [${default}]: ")" result
  echo "${result:-$default}"
}

check_yubikey() {
  if ! ykman info &>/dev/null; then
    error "No YubiKey detected. Please insert your YubiKey and try again."
    return 1
  fi
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
}

cleanup() {
  if [[ -n $TEMP_GNUPGHOME && -d $TEMP_GNUPGHOME ]]; then
    # Kill any gpg-agent running for the temp home
    GNUPGHOME="$TEMP_GNUPGHOME" gpgconf --kill gpg-agent 2>/dev/null || true
    rm -rf "$TEMP_GNUPGHOME"
    info "Cleaned up temporary GNUPGHOME (RAM-backed, no disk traces)."
  fi
}
trap cleanup EXIT

# ANCHOR: preflight
phase_preflight() {
  header "Phase 0: Preflight Checks"

  # Check required tools
  local tools=("gpg" "ykman" "pamu2fcfg" "age-plugin-yubikey" "ssh-to-age")
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
  local serial firmware
  serial=$(ykman info 2>/dev/null | grep "Serial number" | awk '{print $NF}')
  firmware=$(ykman info 2>/dev/null | grep "Firmware version" | awk '{print $NF}')

  info "YubiKey detected:"
  echo "  Serial:   $serial"
  echo "  Firmware: $firmware"

  # Determine key algorithm
  if [[ -n $OPT_ALGO ]]; then
    KEY_ALGO="$OPT_ALGO"
    info "Algorithm forced via --algo: $KEY_ALGO"
    if [[ $KEY_ALGO == "ed25519" ]] && ! version_gte "$firmware" "$MIN_ECC_FIRMWARE"; then
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
  local serial
  serial=$(ykman info 2>/dev/null | grep "Serial number" | awk '{print $NF}')
  YUBIKEY_SERIALS+=("$serial")

  info "YubiKey #$((key_num + 1)) detected (serial: $serial)"

  if prompt_yn "Factory reset the OpenPGP applet? (destroys existing PGP keys on card)"; then
    if $DRY_RUN; then
      dry_run_skip "ykman openpgp reset"
    else
      ykman openpgp reset
      success "OpenPGP applet reset."
    fi
  fi

  if prompt_yn "Factory reset the FIDO2 applet? (destroys existing FIDO2/U2F credentials)"; then
    if $DRY_RUN; then
      dry_run_skip "ykman fido reset"
    else
      ykman fido reset
      success "FIDO2 applet reset."
    fi
  fi
}

# Restore secret subkeys from backup after keytocard has replaced them with stubs.
# This allows provisioning the same subkeys onto another YubiKey.
restore_subkeys() {
  if $DRY_RUN; then
    dry_run_skip "gpg --import $BACKUP_DIR/master-secret.key (restore subkeys for next YubiKey)"
    return
  fi

  info "Restoring subkeys from backup for next YubiKey..."

  # Delete the stub keys first so GPG will accept the full import
  gpg --batch --yes --delete-secret-and-public-key "$KEY_FINGERPRINT" 2>/dev/null || true

  # Re-import the full secret key (master + subkeys)
  gpg --batch --import "$BACKUP_DIR/master-secret.key" 2>/dev/null || {
    error "Failed to restore subkeys from backup."
    exit 1
  }

  success "Subkeys restored from backup."
}

# ANCHOR: keygen
phase_generate_keys() {
  header "Phase 1: PGP Master Key Generation"

  info "Master key will be generated in RAM-backed tmpfs (/dev/shm)."
  info "It will never touch persistent storage."
  echo ""

  # Prompt for key details (skip if provided via CLI)
  local real_name email expiry
  if [[ -n $OPT_NAME ]]; then
    real_name="$OPT_NAME"
  else
    real_name=$(prompt_value "Real name for the key" "$DEFAULT_NAME")
  fi
  if [[ -n $OPT_EMAIL ]]; then
    email="$OPT_EMAIL"
  else
    email=$(prompt_value "Email address" "$DEFAULT_EMAIL")
  fi
  if [[ -n $OPT_EXPIRY ]]; then
    expiry="$OPT_EXPIRY"
  else
    expiry=$(prompt_value "Subkey expiry (e.g., 2y, 1y, 6m)" "$DEFAULT_EXPIRY")
  fi
  info "Key identity: $real_name <$email> (subkey expiry: $expiry)"

  # Create temporary GNUPGHOME on tmpfs
  TEMP_GNUPGHOME=$(mktemp -d /dev/shm/gnupg_XXXXXXXXXX)
  chmod 700 "$TEMP_GNUPGHOME"
  export GNUPGHOME="$TEMP_GNUPGHOME"

  # Write hardened gpg.conf + gpg-agent.conf
  write_gnupg_config

  # Start a fresh agent for this GNUPGHOME
  gpgconf --kill gpg-agent 2>/dev/null || true
  gpg-agent --daemon 2>/dev/null || true

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
  warn "IMPORTANT: You should now set a passphrase on the master key."
  warn "Run the following command in a separate terminal:"
  echo ""
  echo "  GNUPGHOME=$GNUPGHOME gpg --edit-key $KEY_FINGERPRINT passwd"
  echo ""
  read -rp "$(echo -e "${BOLD}Press Enter when done (or skip)...${NC}")"
}
# ANCHOR_END: keygen

# ANCHOR: backup
phase_backup() {
  header "Phase 2: Master Key Backup"

  warn "After moving subkeys to the YubiKey, they CANNOT be extracted."
  warn "You MUST back up the master key now."
  echo ""

  if [[ -n $OPT_BACKUP_DIR ]]; then
    BACKUP_DIR="$OPT_BACKUP_DIR"
    info "Using backup directory from --backup-dir: $BACKUP_DIR"
  else
    BACKUP_DIR=$(prompt_value "Backup directory (use removable media!)" "/tmp/yubikey-backup-$(date +%Y%m%d)")
  fi

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

  # Export master + subkeys
  gpg --armor --export-secret-keys "$KEY_FINGERPRINT" >"$BACKUP_DIR/master-secret.key"

  # Export subkeys only
  gpg --armor --export-secret-subkeys "$KEY_FINGERPRINT" >"$BACKUP_DIR/subkeys-secret.key"

  # Export public key
  gpg --armor --export "$KEY_FINGERPRINT" >"$BACKUP_DIR/public.key"

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
phase_keytocard() {
  header "Phase 3: Move Subkeys to YubiKey"

  check_yubikey

  info "This step moves your subkeys to the YubiKey. This is IRREVERSIBLE."
  info "The subkeys in GNUPGHOME will be replaced with stubs."
  echo ""

  if $DRY_RUN; then
    dry_run_skip "gpg --edit-key $KEY_FINGERPRINT keytocard (3 subkeys)"
    info "Would move Sign, Encrypt, and Authenticate subkeys to YubiKey."
    return
  fi

  info "You need to run the following commands interactively."
  info "Default PINs: user=123456, admin=12345678"
  echo ""
  echo -e "${BOLD}Run this command:${NC}"
  echo ""
  echo "  GNUPGHOME=$GNUPGHOME gpg --edit-key $KEY_FINGERPRINT"
  echo ""
  echo -e "${BOLD}Then execute these steps in the GPG prompt:${NC}"
  echo ""
  echo "  1. Select signature subkey and move to card:"
  echo "     gpg> key 1"
  echo "     gpg> keytocard"
  echo "     Your selection? 1  (Signature key)"
  echo "     gpg> key 1  (deselect)"
  echo ""
  echo "  2. Select encryption subkey and move to card:"
  echo "     gpg> key 2"
  echo "     gpg> keytocard"
  echo "     Your selection? 2  (Encryption key)"
  echo "     gpg> key 2  (deselect)"
  echo ""
  echo "  3. Select authentication subkey and move to card:"
  echo "     gpg> key 3"
  echo "     gpg> keytocard"
  echo "     Your selection? 3  (Authentication key)"
  echo ""
  echo "  4. Save and quit:"
  echo "     gpg> save"
  echo ""

  read -rp "$(echo -e "${BOLD}Press Enter when you have completed the above steps...${NC}")"

  # Verify keys are on card
  info "Verifying keys are on the YubiKey..."
  local card_status
  card_status=$(GNUPGHOME="$GNUPGHOME" gpg --card-status 2>/dev/null || true)

  if echo "$card_status" | grep -q "Signature key"; then
    success "Signature key found on card."
  else
    warn "Signature key not detected on card."
  fi

  if echo "$card_status" | grep -q "Encryption key"; then
    success "Encryption key found on card."
  else
    warn "Encryption key not detected on card."
  fi

  if echo "$card_status" | grep -q "Authentication key"; then
    success "Authentication key found on card."
  else
    warn "Authentication key not detected on card."
  fi
}
# ANCHOR_END: keytocard

phase_pins() {
  header "Phase 4: YubiKey PIN Configuration"

  check_yubikey

  info "Default PINs: user=123456, admin=12345678"
  echo ""

  if $DRY_RUN; then
    dry_run_skip "ykman openpgp access change-pin"
    dry_run_skip "ykman openpgp access change-admin-pin"
    info "Would prompt to change PINs and set cardholder name."
    return
  fi

  if prompt_yn "Change the OpenPGP user PIN?"; then
    ykman openpgp access change-pin
    success "User PIN changed."
  fi

  if prompt_yn "Change the OpenPGP admin PIN?"; then
    ykman openpgp access change-admin-pin
    success "Admin PIN changed."
  fi

  if prompt_yn "Set cardholder name on the YubiKey?"; then
    local name
    name=$(prompt_value "Cardholder name" "$DEFAULT_NAME")
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

  full_output=$(age-plugin-yubikey --generate \
    --slot "$slot" \
    --name "sops-nix" \
    --pin-policy once \
    --touch-policy always 2>&1) || {
    error "age-plugin-yubikey generation failed."
    warn "You can retry manually: age-plugin-yubikey --generate"
    AGE_IDENTITIES+=("")
    AGE_RECIPIENTS+=("")
    AGE_FULL_OUTPUTS+=("")
    return
  }

  # Extract the identity line and recipient
  identity=$(echo "$full_output" | grep "^AGE-PLUGIN-YUBIKEY-" || true)
  recipient=$(echo "$full_output" | grep "^age1yubikey1q" || true)

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
    local pubkey_file="/tmp/yubikey-pubkey-$$.asc"
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

  # Write summary to a file for reference
  local summary_file
  summary_file="/tmp/yubikey-onboard-summary-$(date +%Y%m%d-%H%M%S).txt"
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
phase_import_from_backup() {
  header "Importing Master Key from Backup"

  local backup_path="$OPT_FROM_BACKUP"

  # Validate backup path
  if [[ ! -f $backup_path && ! -d $backup_path ]]; then
    error "Backup path does not exist: $backup_path"
    exit 1
  fi

  # If a directory was given, look for the master key file inside it
  local key_file="$backup_path"
  if [[ -d $backup_path ]]; then
    if [[ -f "$backup_path/master-secret.key" ]]; then
      key_file="$backup_path/master-secret.key"
    else
      error "No master-secret.key found in $backup_path"
      error "Expected a file produced by a previous onboarding run."
      exit 1
    fi
    # Use the directory as backup dir for subkey restoration during multi-key provisioning
    BACKUP_DIR="$backup_path"
  else
    BACKUP_DIR="$(dirname "$backup_path")"
  fi

  info "Importing master key from: $key_file"

  # Create temporary GNUPGHOME on tmpfs
  TEMP_GNUPGHOME=$(mktemp -d /dev/shm/gnupg_XXXXXXXXXX)
  chmod 700 "$TEMP_GNUPGHOME"
  export GNUPGHOME="$TEMP_GNUPGHOME"

  # Write hardened gpg.conf + gpg-agent.conf
  write_gnupg_config

  gpgconf --kill gpg-agent 2>/dev/null || true
  gpg-agent --daemon 2>/dev/null || true

  if $DRY_RUN; then
    dry_run_skip "gpg --import $key_file"
    KEY_FINGERPRINT="DRY_RUN_FINGERPRINT_0000000000000000"
    info "Would import master key and list existing subkeys."
    return
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
  local subkey_count
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
    echo ""
    gpg --list-keys --with-keygrip "$KEY_FINGERPRINT"
  else
    info "Found $subkey_count subkey(s). Proceeding with existing subkeys."
  fi

  # Re-export the (potentially updated) master key for multi-key subkey restoration
  gpg --armor --export-secret-keys "$KEY_FINGERPRINT" >"$BACKUP_DIR/master-secret.key"
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
  serial=$(ykman info 2>/dev/null | grep "Serial number" | awk '{print $NF}')
  firmware=$(ykman info 2>/dev/null | grep "Firmware version" | awk '{print $NF}')
  success "YubiKey detected (serial: $serial, firmware: $firmware)"

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
  for cfg in "${config_files[@]}"; do
    if [[ -f $cfg ]]; then
      if grep -q "$serial" "$cfg" 2>/dev/null; then
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
  phase_summary

  success "All done! $NUM_KEYS YubiKey(s) provisioned."
  success "Remember to clean up backup files from insecure locations."
}

# ANCHOR_END: main
main "$@"
