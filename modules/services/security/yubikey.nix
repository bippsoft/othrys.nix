# modules/services/security/yubikey.nix
# YubiKey authentication over U2F PAM, GPG and SSH, hardened per drduh's guide.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # ANCHOR: yubikey-options
  options.othrys.services.security.yubikey = {
    enable = lib.mkEnableOption "YubiKey authentication (U2F + GPG + SSH)";

    # U2F PAM options
    u2fMappings = lib.mkOption {
      # One pamu2fcfg credential: key handle, public key, COSE type and an
      # options field, comma-separated. A colon or a newline would start
      # another user's line in the mappings file.
      type = lib.types.attrsOf (lib.types.listOf (lib.types.strMatching "[A-Za-z0-9+/=_.-]+(,[A-Za-z0-9+/=_.-]*)+"));
      default = {};
      description = ''
        U2F key mappings per user. Generated with:
          pamu2fcfg -n -o pam://yubi

        That command prints each credential with a leading colon, which
        joins it to a user's line in a mappings file. Leave the colon out
        here, since each list entry is one credential.

        Keys are stored in /nix/store (read-only) for security. Any
        non-empty mapping turns pam_u2f on for the services in
        `u2fServices`.
      '';
      example = {
        alice = [
          "<KeyHandle1>,<UserKey1>,<CoseType1>,<Options1>"
          "<KeyHandle2>,<UserKey2>,<CoseType2>,<Options2>"
        ];
      };
    };

    u2fOrigin = lib.mkOption {
      type = lib.types.str;
      default = "pam://yubi";
      description = "U2F origin for cross-machine portability.";
    };

    u2fRequirePassword = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Require a password in addition to the touch, rather than accepting the
        touch alone.

        With this on, pam_u2f is inserted as `required` in every service in
        `u2fServices`, so both the password and the touch must succeed and the
        key is a second factor. The control applies to the whole PAM service
        and not to one user, so every account that authenticates through one
        of those services needs an enrolled credential, and an account with
        none is locked out of them while other accounts keep working. Enrol
        and test a key for every such account before turning it on. The
        module refuses the setting while any normal user of the host has no
        mapping, apart from the accounts named in `u2fExemptUsers`.

        With this off, pam_u2f is `sufficient`: a touch on an enrolled key
        satisfies the service with no password, which is authentication by
        possession alone. Whoever holds the token holds root, and a token
        left in a laptop is a token in someone's hand. An account with no
        mapping falls through to its password, so nothing is locked out.
      '';
    };

    u2fExemptUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["deploy"];
      description = ''
        Normal users that have no entry in `u2fMappings` on purpose. With
        `u2fRequirePassword` on, the module refuses a host where a normal
        user has no mapping, since that account fails every service in
        `u2fServices`. An account that never authenticates through them, such
        as one reached over SSH alone, is named here and the check passes it
        over. It stays locked out of those services.
      '';
    };

    u2fServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["login" "sudo" "greetd" "polkit-1" "hyprlock" "swaylock"];
      description = ''
        PAM services that take the YubiKey, by their names under
        `security.pam.services`. Console login, sudo, the greeter, polkit
        prompts and the two screen lockers by default. `su` and `sshd` are
        left out on purpose: `su` is how root is reached from a console with
        no key at hand, and `sshd` authenticates with keys of its own. A
        service listed here that the host does not run is harmless.
      '';
    };

    # GPG/SSH options
    sshKeygrips = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "GPG keygrips to authorize for SSH authentication.";
      example = ["0123456789ABCDEF0123456789ABCDEF01234567"];
    };

    pinentryPackage = lib.mkOption {
      type = lib.types.package;
      default =
        if config.othrys.desktop.graphical
        then pkgs.pinentry-qt
        else pkgs.pinentry-curses;
      defaultText = lib.literalExpression "pkgs.pinentry-qt on graphical hosts (othrys.desktop.graphical), pkgs.pinentry-curses otherwise";
      description = ''
        Pinentry program for GPG/SSH PIN prompts. A graphical pinentry on a
        headless host cannot render, silently breaking every GPG and SSH
        authentication, which is why the terminal fallback is the default.
      '';
    };
  };
  # ANCHOR_END: yubikey-options
}
