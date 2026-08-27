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

  config = lib.mkIf cfg.enable {
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

    # Essential user CLI tools go through home-manager, so only when it
    # manages the environment (attrset-level guard, see modules/system/nix.nix).
    home-manager.users = lib.mkIf cfg.homeManaged {
      ${username}.home.packages = with pkgs; [
        tree
        jq
        just
      ];
    };
  };
}
