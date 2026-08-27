# modules/system/users.nix
# User account creation, shell, and essential packages
{
  config,
  lib,
  pkgs,
  ...
}: let
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

    initialPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Initial password for bootstrap (cleared after first login).";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "config.sops.secrets.\"users/alice/password\".path";
      description = "Path to file containing hashed password (injected by host config).";
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
        assertion = cfg.passwordFile != null || cfg.initialPassword != null;
        message = "othrys.system.users: set passwordFile or initialPassword, or the '${username}' account is created with no password.";
      }
    ];

    # User creation, secrets-agnostic since passwordFile is injected by the host config
    users.users.${username} = {
      isNormalUser = true;
      description = username;

      extraGroups = ["wheel"] ++ cfg.extraGroups;

      shell = cfg.defaultShell;

      # Use injected password file, or fall back to initial password for bootstrap
      hashedPasswordFile = cfg.passwordFile;
      initialPassword = lib.mkIf (cfg.passwordFile == null) cfg.initialPassword;
    };

    # Lock down user management when using password file
    users.mutableUsers = cfg.passwordFile == null;

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
