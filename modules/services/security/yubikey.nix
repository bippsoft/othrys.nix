# modules/services/security/yubikey.nix
# YubiKey authentication over U2F PAM, GPG and SSH, hardened per drduh's guide.
#
# The options and the user's GnuPG and agent configuration, which both
# platforms write. yubikey.nixos.nix and yubikey.darwin.nix hold the rest.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.services.security.yubikey;

  # Generate sshcontrol file content
  sshcontrolContent = lib.concatStringsSep "\n" cfg.sshKeygrips;
in {
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
        `u2fServices`. NixOS only, and a darwin host refuses a mapping,
        since nix-darwin manages the sudo service alone and othrys puts no
        pam_u2f line there.
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
        if !config.othrys.desktop.graphical
        then pkgs.pinentry-curses
        else if pkgs.stdenv.hostPlatform.isDarwin
        then pkgs.pinentry_mac
        else pkgs.pinentry-qt;
      defaultText = lib.literalExpression "pkgs.pinentry-curses unless othrys.desktop.graphical, and on a graphical host pkgs.pinentry_mac on nix-darwin and pkgs.pinentry-qt otherwise";
      description = ''
        Pinentry program for GPG/SSH PIN prompts. A graphical pinentry on a
        headless host cannot render, silently breaking every GPG and SSH
        authentication, which is why the terminal fallback is the default.
      '';
    };
  };
  # ANCHOR_END: yubikey-options

  config = lib.mkIf cfg.enable {
    othrys.internal.homeConfig."services.security.yubikey" = {
      # Create sshcontrol file with authorized keygrips
      home.file.".gnupg/sshcontrol" = lib.mkIf (cfg.sshKeygrips != []) {
        text = sshcontrolContent + "\n";
      };

      # GPG configuration with hardening
      # https://github.com/drduh/config/blob/master/gpg.conf
      programs.gpg = {
        enable = true;

        # Prevent pcscd and gpg-agent conflicts
        # https://support.yubico.com/hc/en-us/articles/4819584884124-Resolving-GPG-s-CCID-conflicts
        scdaemonSettings = {
          disable-ccid = true;
        };

        settings = {
          # Cipher preferences
          personal-cipher-preferences = "AES256 AES192 AES";
          personal-digest-preferences = "SHA512 SHA384 SHA256";
          personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
          default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";

          # Algorithm selection
          cert-digest-algo = "SHA512";
          s2k-digest-algo = "SHA512";
          s2k-cipher-algo = "AES256";

          # Display options
          charset = "utf-8";
          fixed-list-mode = true;
          no-comments = true;
          no-emit-version = true;
          keyid-format = "0xlong";
          list-options = "show-uid-validity";
          verify-options = "show-uid-validity";
          with-fingerprint = true;

          # Security
          require-cross-certification = true;
          no-symkey-cache = true;
          use-agent = true;
          throw-keyids = true;
        };
      };

      # GPG agent with SSH support
      # https://github.com/drduh/config/blob/master/gpg-agent.conf
      services.gpg-agent = {
        enable = true;
        enableSshSupport = true;
        enableZshIntegration = true;
        enableBashIntegration = true;

        # Short cache times for security
        defaultCacheTtl = 60;
        maxCacheTtl = 120;

        # Pinentry for PIN prompts (terminal on headless, Qt or pinentry-mac on desktop)
        pinentry.package = cfg.pinentryPackage;

        extraConfig = ''
          ttyname $GPG_TTY
        '';
      };
    };
  };
}
