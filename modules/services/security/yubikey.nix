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

  # PAM stanza shared by the login and sudo services.
  u2fPam = {
    enable = true;
    control =
      if cfg.u2fRequirePassword
      then "required"
      else "sufficient";
  };

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
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {};
      description = ''
        U2F key mappings per user. Generated with:
          pamu2fcfg -n -o pam://yubi

        Keys are stored in /nix/store (read-only) for security.
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
      default = false;
      description = ''
        Require a password in addition to the touch, rather than accepting the
        touch alone.

        pam_u2f is inserted as `sufficient` by default, which means a touch on
        an enrolled key satisfies login and sudo with no password. That is
        single-factor authentication by possession. Whoever holds the token
        holds root, and a token left in a laptop is a token in someone's hand.
        The tradeoff is deliberate, since it is also what makes the key
        convenient.

        Setting this to true switches the control to `required`, so both the
        password and the touch must succeed. Enrol and test a key before
        turning it on, because a host with no working key and a required U2F
        factor cannot be logged into.
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
    # Prevent a U2F-for-login lockout, since any non-empty u2fMappings turns on U2F for
    # login, so the logging-in user must have a mapping or they can't log in.
    assertions = [
      {
        # Only meaningful when othrys manages the primary user, since otherwise the
        # host owns its accounts and we can't know who logs in.
        assertion = !usersEnabled || cfg.u2fMappings == {} || builtins.hasAttr username cfg.u2fMappings;
        message = "othrys.services.security.yubikey: u2fMappings is non-empty but has no entry for the login user '${username}'. U2F is required for login, so this would lock '${username}' out. Add a u2fMappings.\"${username}\" entry.";
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

    # Allows YubiKey to replace password for sudo/login

    security.pam.u2f = lib.mkIf (cfg.u2fMappings != {}) {
      enable = true;
      settings = {
        # Cross-machine portability
        origin = cfg.u2fOrigin;

        # Store mappings in read-only /nix/store (NOT user-writable ~/.config)
        authfile = pkgs.writeText "u2f-mappings" u2fMappingsContent;

        # User prompts
        interactive = true; # "Insert your U2F device, then press ENTER"
        cue = true; # "Please touch the device"
      };
    };

    # Enable U2F for sudo and login. The control decides whether the touch
    # replaces the password ("sufficient", possession alone) or is demanded
    # alongside it ("required", two factors). See u2fRequirePassword.
    security.pam.services = lib.mkIf (cfg.u2fMappings != {}) {
      login.u2f = u2fPam;
      sudo.u2f = u2fPam;
    };

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
