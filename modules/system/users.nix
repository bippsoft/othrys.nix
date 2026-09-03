# modules/system/users.nix
# User account creation, shell, and essential packages
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  username = config.othrys.system.user.name;
  cfg = config.othrys.system.users;
in {
  options.othrys.system.users = {
    enable = lib.mkEnableOption "User account configuration";

    homeManager = {
      enable =
        lib.mkEnableOption "home-manager management of the primary user's environment"
        // {default = true;};
    };

    # Derived and read-only, the single flag every module's home-manager guard
    # reads. Account creation (enable) and environment management
    # (homeManager.enable) are separate concerns, since a server may want a login
    # account (e.g. for an admin, or a user a webapp runs under) without
    # home-manager owning its dotfiles.
    homeManaged = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = cfg.enable && cfg.homeManager.enable;
      defaultText = lib.literalExpression "othrys.system.users.enable && othrys.system.users.homeManager.enable";
      description = "Whether home-manager manages the primary user (derived; do not set).";
    };

    defaultShell = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bash;
      description = "Default shell for the user.";
    };

    initialHashedPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "$y$j9T$...";
      description = ''
        Hashed password used to bootstrap the account on first boot, for the
        window before a secrets provider is available. Generate one with
        `mkpasswd -m yescrypt`.

        The hash is written into the world-readable Nix store and stays there
        for the life of every generation that references it, so treat it as
        public and offline-crackable. It is a bootstrap mechanism, and NixOS
        does not clear or expire it. Move the host to passwordFile once secrets
        decrypt on boot.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = lib.literalExpression "config.sops.secrets.\"users/alice/password\".path";
      description = "Path to a runtime file holding the hashed password, injected by the host configuration. The preferred form, since nothing reaches the store.";
    };

    mutableUsers = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        users.mutableUsers. False keeps accounts fully declarative, so passwd
        and useradd changes do not survive a rebuild. Set it to true on a host
        where accounts are managed outside Nix.

        This is stated rather than inferred. It was previously derived from
        whether passwordFile happened to be null, which flipped a security
        property as a side effect of an unrelated option.
      '';
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional groups for the user (merged with [\"wheel\"]).";
    };
  };

  # Every othrys module that configures the primary user's environment writes
  # here, keyed by its own option path, and this module is the only one that
  # writes home-manager.users.
  #
  # The consumer contract requires those writes to sit behind homeManaged at
  # the attrset level, since a leaf-level guard still materializes the
  # home-manager user and trips NixOS's account assertions on a host with no
  # primary user. Routing every module through one option means no module can
  # spell that guard wrongly, and it lets flake/checks/ enforce the rule as a
  # prohibition (nothing but this file writes home-manager.users) rather than a
  # correlation (a module that writes it must also mention homeManaged). A
  # prohibition cannot be satisfied by accident.
  #
  # A module with a second condition wraps its own value in lib.mkIf. The key
  # then disappears when the condition is false, so it is neither written nor
  # reported below.
  # lib.types.raw rather than attrsOf anything, and the difference is not
  # cosmetic. Every ordinary option type resolves definition priorities at its
  # own level, so a module writing `gtk.gtk4.theme = lib.mkForce null` through
  # an `anything`-typed option would have that mkForce discharged here and
  # arrive at home-manager as a plain definition, silently losing to upstream
  # Stylix. raw passes each value through unprocessed, so mkForce and mkDefault
  # inside a module's contribution still reach home-manager.users and still
  # win or lose against upstream as the module intended. A top-level mkIf is
  # unaffected either way, since definition properties are discharged before
  # the type sees the value.
  #
  # raw also refuses to merge two definitions of the same key. Keys are option
  # paths and therefore unique per module, so a collision is a bug and failing
  # loudly is the right answer.
  options.othrys.internal.homeConfig = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = {};
    internal = true;
    example = lib.literalExpression ''{ "apps.ghostty" = { programs.ghostty.enable = true; }; }'';
    description = "Per-module home-manager configuration for the primary user, keyed by option path, spliced by othrys.system.users.";
  };

  config = lib.mkMerge [
    {
      # Both of these sit outside the enable guard. The write is already gated
      # on homeManaged, which implies enable, and the warning reports the case
      # where enable is off, so gating it on enable could never fire.
      home-manager.users = lib.mkIf cfg.homeManaged {
        ${username} = lib.mkMerge (
          # Essential user CLI tools, kept here rather than in
          # environment.systemPackages so they follow the user.
          [{home.packages = with pkgs; [tree jq just];}]
          ++ lib.attrValues config.othrys.internal.homeConfig
        );
      };

      # Most modules that configure the user write nothing else, so on a host
      # without a managed user `enable = true` silently does nothing at all.
      # One warning naming every such module, since thirty-two near-identical
      # ones on every rebuild is how a diagnostic gets scrolled past.
      # attrNames returns sorted, so the list is stable across evaluations.
      warnings = lib.optional (!cfg.homeManaged && config.othrys.internal.homeConfig != {}) ''
        othrys.system.users.homeManaged is false, so home-manager configuration was
        skipped for: ${lib.concatStringsSep ", " (lib.attrNames config.othrys.internal.homeConfig)}.

        Where a module writes nothing but user configuration, enabling it on this
        host has no effect at all. Set othrys.system.users.enable and
        othrys.system.users.homeManager.enable to apply them.
      '';
    }

    (lib.mkIf cfg.enable {
      # Fail loudly rather than create a passwordless/locked account on first boot.
      assertions = [
        {
          assertion = cfg.passwordFile != null || cfg.initialHashedPassword != null;
          message = "othrys.system.users: set passwordFile or initialHashedPassword, or the '${username}' account is created with no password.";
        }
      ];

      # User creation, secrets-agnostic since passwordFile is injected by the host config
      users.users.${username} = {
        isNormalUser = true;
        description = username;

        extraGroups = ["wheel"] ++ cfg.extraGroups;

        shell = cfg.defaultShell;

        # Use the injected password file, or fall back to the bootstrap hash.
        hashedPasswordFile = cfg.passwordFile;
        initialHashedPassword = lib.mkIf (cfg.passwordFile == null) cfg.initialHashedPassword;
      };

      users.mutableUsers = cfg.mutableUsers;

      # Essential system and recovery packages, kept minimal since user CLI
      # tools go to home-manager.
      environment.systemPackages = with pkgs; [
        curl
        wget
        vim
        unzip
        zip
        lsof
        pciutils
      ];
    })
  ];
}
