# modules/desktop/keyring.nix
# Secret Service provider for the graphical session, on gnome-keyring or pass
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.desktop.keyring;
  username = config.othrys.system.user.name;
  homeManaged = config.othrys.system.users.homeManaged;
  niriEnabled = config.othrys.desktop.compositors.niri.enable;

  gnomeKeyring = cfg.enable && cfg.provider == "gnome-keyring";
  pass = cfg.enable && cfg.provider == "pass";
  passwordless = gnomeKeyring && cfg.passwordless;

  # The initrd unlocks every device listed here, and disko writes its LUKS
  # containers into the same option, so a host partitioned by
  # othrys.system.disko and a host that set LUKS up by hand both show up.
  diskEncrypted = config.boot.initrd.luks.devices != {};

  # gnome-keyring reads a keyring file in its plain text format as a keyring
  # without a password, and it never asks to unlock one. The `default` file
  # names the keyring that new secrets go to, without the `.keyring` suffix.
  keyringName = "Default_keyring";
  keyringFile = pkgs.writeText "${keyringName}.keyring" ''
    [keyring]
    display-name=Default keyring
    ctime=0
    mtime=0
    lock-on-idle=false
    lock-after=false
  '';
  defaultFile = pkgs.writeText "keyring-default" keyringName;

  # Runs at every Home Manager activation and writes only when neither
  # keyring exists. A login keyring made earlier with a password therefore
  # stays as it is, and its owner removes it to start over without one.
  passwordlessHome = {
    home.activation.othrysPasswordlessKeyring = {
      after = ["writeBoundary"];
      before = [];
      data = ''
        keyrings="$HOME/.local/share/keyrings"
        if [ ! -e "$keyrings/login.keyring" ] && [ ! -e "$keyrings/${keyringName}.keyring" ]; then
          run ${pkgs.coreutils}/bin/mkdir -p -m 0700 "$keyrings"
          run ${pkgs.coreutils}/bin/install -m 0600 ${keyringFile} "$keyrings/${keyringName}.keyring"
          run ${pkgs.coreutils}/bin/install -m 0600 ${defaultFile} "$keyrings/default"
        fi
      '';
    };
  };

  # The unit takes the store as an absolute path on its command line, where
  # no shell expands `$HOME`.
  passStore = "${config.users.users.${username}.home}/${cfg.pass.directory}";

  # `pass init` would write the same file and then re-encrypt the store,
  # which calls gpg and needs the key at hand. Writing the file alone is
  # enough for a new store, and a store that already names its key is left
  # as it is. Home Manager hands PASSWORD_STORE_DIR to pass-secret-service
  # as its store path.
  passHome = {
    programs.password-store = {
      enable = true;
      settings.PASSWORD_STORE_DIR = passStore;
    };

    services.pass-secret-service.enable = true;

    home.activation.othrysPassStore = {
      after = ["writeBoundary"];
      before = [];
      data = ''
        store=${lib.escapeShellArg passStore}
        if [ ! -e "$store/.gpg-id" ]; then
          run ${pkgs.coreutils}/bin/mkdir -p -m 0700 "$store"
          run ${pkgs.coreutils}/bin/install -m 0600 ${pkgs.writeText "gpg-id" "${cfg.pass.gpgKey}\n"} "$store/.gpg-id"
        fi
      '';
    };
  };
in {
  # ANCHOR: keyring-options
  options.othrys.desktop.keyring = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.othrys.desktop.graphical;
      defaultText = lib.literalExpression "config.othrys.desktop.graphical";
      example = false;
      description = ''
        Whether to run a Secret Service provider in the graphical session,
        which `provider` selects. Browsers, mail clients and tray
        applications store credentials in the Secret Service, and without a
        provider they fall back to a plain file or ask again on every start.
        It is on by default on a graphical host. A host that runs another
        provider, such as KeePassXC or KWallet, turns it off, since two
        providers compete for the same D-Bus name.
      '';
    };

    provider = lib.mkOption {
      type = lib.types.enum ["gnome-keyring" "pass"];
      default = "gnome-keyring";
      example = "pass";
      description = ''
        Which program serves the Secret Service.

        `gnome-keyring` encrypts its store with a password and unlocks it
        from the login password through PAM. It asks for that password the
        first time a secret is read unless the login passed one that
        matches, or `passwordless` created the store without one. A login
        with a hardware key alone passes no password, and a touch yields a
        signature and no secret, so nothing can unlock the store there.

        `pass` runs `pass-secret-service` for the primary user over a `pass`
        password store, where each secret is a file encrypted to the OpenPGP
        key named in `pass.gpgKey`. With that key on a hardware token,
        reading a secret needs the token, its PIN once for each agent
        session, and a touch on each read when the token's touch policy for
        decryption is set to always. gnome-keyring is turned off, since only
        one provider can own the D-Bus name. Home Manager has to manage the
        primary user, and the host needs a gpg-agent with a pinentry, which
        `othrys.services.security.yubikey` sets up.
      '';
    };

    passwordless = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to create the gnome-keyring store with no password, so that
        nothing ever asks to unlock it. It applies to the `gnome-keyring`
        provider only.

        The store is then plain files under `~/.local/share/keyrings`. File
        permissions protect it from other accounts, and disk encryption
        protects it from someone holding the powered-off machine. Nothing
        else does, so any program running as the user and anyone who can
        read the mounted disk reads every secret. The module refuses the
        option on a host with no encrypted disk unless
        `allowUnencryptedDisk` is set.

        The keyring file is written when Home Manager activates and neither
        `login.keyring` nor `Default_keyring.keyring` exists. A keyring that
        already exists is never replaced, so a host that had a keyring with
        a password keeps it until its owner removes it.
      '';
    };

    allowUnencryptedDisk = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Accept `passwordless` on a host that declares no LUKS device in
        `boot.initrd.luks.devices`. Every stored secret then sits on the
        disk in plain files, readable by whoever holds the disk.
      '';
    };

    pass = {
      gpgKey = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "(0x)?[0-9A-Fa-f]{8,64}");
        default = null;
        example = "0123456789ABCDEF0123456789ABCDEF01234567";
        description = ''
          Key id or fingerprint of the OpenPGP key the password store is
          encrypted to. Required with `provider = "pass"`. A new store is
          initialised for it by writing its `.gpg-id` file, and a store that
          already has one is left alone. The public key has to be in the
          user's GnuPG keyring and trusted, which the module does not
          arrange.
        '';
      };

      directory = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*";
        default = ".local/share/password-store";
        example = ".password-store";
        description = ''
          The password store, relative to the primary user's home
          directory. `pass` and `pass-secret-service` are both pointed at
          it, and it is persisted at mode 0700 under impermanence.
        '';
      };
    };
  };
  # ANCHOR_END: keyring-options

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = pass -> cfg.pass.gpgKey != null;
          message = "othrys.desktop.keyring.provider is \"pass\", which encrypts each secret to an OpenPGP key: set othrys.desktop.keyring.pass.gpgKey to its key id or fingerprint.";
        }
        {
          assertion = pass -> homeManaged;
          message = "othrys.desktop.keyring.provider is \"pass\", which runs pass-secret-service as a Home Manager user service: othrys.system.users.homeManaged is false, so enable othrys.system.users, leave othrys.system.users.homeManager.enable on and import othrys.nixosModules.home with the Home Manager module.";
        }
        {
          assertion = pass -> !config.services.gnome.gnome-keyring.enable;
          message = "othrys.desktop.keyring.provider is \"pass\" and services.gnome.gnome-keyring.enable is forced on, so two Secret Service providers would compete for one D-Bus name. Drop the override, or set othrys.desktop.keyring.provider to \"gnome-keyring\".";
        }
        {
          assertion = cfg.passwordless -> cfg.provider == "gnome-keyring";
          message = "othrys.desktop.keyring.passwordless creates a gnome-keyring store and means nothing with othrys.desktop.keyring.provider = \"pass\". Turn one of the two off.";
        }
        {
          assertion = passwordless -> homeManaged;
          message = "othrys.desktop.keyring.passwordless writes the keyring file from Home Manager: othrys.system.users.homeManaged is false, so enable othrys.system.users, leave othrys.system.users.homeManager.enable on and import othrys.nixosModules.home with the Home Manager module.";
        }
        {
          assertion = passwordless -> (diskEncrypted || cfg.allowUnencryptedDisk);
          message = "othrys.desktop.keyring.passwordless stores every secret in plain files under ~/.local/share/keyrings, and this host declares no LUKS device in boot.initrd.luks.devices, so an unencrypted disk would hold them readable by whoever takes it. Encrypt the disk, or set othrys.desktop.keyring.allowUnencryptedDisk on a host that accepts that.";
        }
      ];

      services.gnome.gnome-keyring.enable = lib.mkIf gnomeKeyring true;

      # The greeter hands the login password to the keyring, which unlocks it
      # with the session. Without this the first application that asks for a
      # secret raises a second password prompt. A store with no password has
      # nothing to unlock, and pass is unlocked by the OpenPGP key.
      security.pam.services = lib.mkIf (gnomeKeyring && !cfg.passwordless && config.othrys.desktop.login.enable) {
        greetd.enableGnomeKeyring = true;
      };

      othrys.internal.persist."desktop.keyring" = {
        user.directories = [
          {
            directory =
              if pass
              then cfg.pass.directory
              else ".local/share/keyrings";
            mode = "0700";
          }
        ];
      };

      # With no key named the assertion above already refuses the host, and
      # the registry entry is dropped so that the refusal is what is reported.
      othrys.internal.homeConfig."desktop.keyring" = lib.mkIf (passwordless || (pass && cfg.pass.gpgKey != null)) (
        if pass
        then passHome
        else passwordlessHome
      );
    })

    # niri-flake's NixOS module enables gnome-keyring on every niri host as a
    # plain definition, which the option default cannot answer. A definition
    # one step above it lets the option turn the keyring off there, and a host
    # that wants the last word still has mkForce. With the keyring option off
    # it is written on niri hosts only, so that elsewhere a host's own
    # gnome-keyring setting is left alone. With pass it is written on every
    # host, since pass-secret-service then owns the D-Bus name.
    (lib.mkIf (pass || (!cfg.enable && niriEnabled)) {
      services.gnome.gnome-keyring.enable = lib.mkOverride 90 false;
    })
  ];
}
