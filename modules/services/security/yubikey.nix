# modules/services/security/yubikey.nix
# YubiKey authentication over U2F PAM, GPG and SSH, hardened per drduh's guide.
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.services.security.yubikey;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # Generate sshcontrol file content
  sshcontrolContent = lib.concatStringsSep "\n" cfg.sshKeygrips;

  # PAM stanza for every service in u2fServices. nixpkgs' global
  # security.pam.u2f.enable would insert pam_u2f into every PAM service on
  # the host as `sufficient`, su, polkit and the lockers included, so the
  # module names the services and sets the control on each one instead.
  u2fPam = {
    enable = true;
    control =
      if cfg.u2fRequirePassword
      then "required"
      else "sufficient";
  };
  u2fEnabled = cfg.u2fMappings != {};

  # Generate U2F mappings file content
  u2fMappingsContent = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (user: keys: "${user}:${lib.concatStringsSep ":" keys}") cfg.u2fMappings
  );
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
        and test a key for every such account before turning it on, and the
        module refuses the setting when the primary user has no mapping.

        With this off, pam_u2f is `sufficient`: a touch on an enrolled key
        satisfies the service with no password, which is authentication by
        possession alone. Whoever holds the token holds root, and a token
        left in a laptop is a token in someone's hand. An account with no
        mapping falls through to its password, so nothing is locked out.
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

  config = lib.mkIf cfg.enable {
    # With `required`, an account with no mapping cannot pass any listed
    # service, so the primary user needs one. With `sufficient` a missing
    # mapping falls through to the password and locks nobody out. Only the
    # primary user is known here; the host owns its other accounts.
    assertions = [
      {
        assertion = !(usersEnabled && u2fEnabled && cfg.u2fRequirePassword) || builtins.hasAttr username cfg.u2fMappings;
        message = "othrys.services.security.yubikey: u2fRequirePassword is on and u2fMappings has no entry for '${username}', which would lock that user out of ${lib.concatStringsSep ", " cfg.u2fServices}. Add a u2fMappings.\"${username}\" entry, or set u2fRequirePassword = false.";
      }
    ];

    environment.systemPackages = with pkgs; [
      gnupg
      age-plugin-yubikey
      ssh-to-age
      yubikey-personalization
      yubikey-manager
      pam_u2f # For generating new key mappings
    ];

    # The module settings are global and every service inherits them. The
    # global enable stays off, since it would put pam_u2f into every PAM
    # service on the host; the services in u2fServices turn it on each.
    security.pam.u2f = lib.mkIf u2fEnabled {
      settings = {
        # Cross-machine portability
        origin = cfg.u2fOrigin;

        # Store mappings in read-only /nix/store (NOT user-writable ~/.config)
        authfile = pkgs.writeText "u2f-mappings" u2fMappingsContent;

        # No "press ENTER" prompt. A greeter, polkit or a locker has no
        # terminal to answer it on, and a console login takes the touch
        # straight away; the cue says what is wanted.
        interactive = false;
        cue = true; # "Please touch the device"
      };
    };

    # The control decides whether the touch replaces the password
    # ("sufficient", possession alone) or is demanded alongside it
    # ("required", two factors). See u2fRequirePassword.
    security.pam.services = lib.mkIf u2fEnabled (lib.genAttrs cfg.u2fServices (_: {u2f = u2fPam;}));

    services.pcscd.enable = true;

    services.udev.packages = with pkgs; [
      yubikey-personalization
    ];

    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        {
          directory = ".gnupg";
          mode = "0700";
        }
      ];
    };

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

        # Pinentry for PIN prompts (terminal on headless, Qt on desktop)
        pinentry.package = cfg.pinentryPackage;

        extraConfig = ''
          ttyname $GPG_TTY
        '';
      };
    };
  };
}
