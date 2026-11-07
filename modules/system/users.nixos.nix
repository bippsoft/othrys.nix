# modules/system/users.nixos.nix
# The NixOS implementation of othrys.system.users
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.system.users;
in {
  imports = [./users.nix];

  config = lib.mkIf cfg.enable {
    # Fail loudly rather than create a passwordless/locked account on first boot.
    assertions = [
      {
        assertion = cfg.passwordFile != null || cfg.initialHashedPassword != null;
        message = "othrys.system.users: set passwordFile or initialHashedPassword, or the '${username}' account is created with no password.";
      }
    ];

    # NixOS reads hashedPasswordFile in the `users` activation step, and
    # sops-nix installs ordinary secrets after it. A sops secret declared
    # with neededForUsers lands under /run/secrets-for-users/ instead, so a
    # /run/secrets/ path is the one that is missing at the moment it is
    # read. The result is a shadow entry nobody can log in with, and the
    # host reports nothing, so this says so at evaluation.
    warnings = lib.optional (cfg.passwordFile != null && lib.hasPrefix "/run/secrets/" cfg.passwordFile) ''
      othrys.system.users.passwordFile is ${cfg.passwordFile}, under /run/secrets/.
      sops-nix installs that path after the users activation step reads it,
      so the '${username}' account comes up with no usable password. Declare
      the secret with neededForUsers = true and use its path, which is under
      /run/secrets-for-users/.
    '';

    # User creation, secrets-agnostic since passwordFile is injected by the host config
    users.users.${username} = {
      isNormalUser = true;
      description = username;

      extraGroups = lib.optional cfg.wheel "wheel" ++ cfg.extraGroups;

      shell = cfg.defaultShell;

      # Use the injected password file, or fall back to the bootstrap hash.
      hashedPasswordFile = cfg.passwordFile;
      initialHashedPassword = lib.mkIf (cfg.passwordFile == null) cfg.initialHashedPassword;
    };

    users.mutableUsers = cfg.mutableUsers;

    # Essential system and recovery packages, kept minimal since user CLI
    # tools go to Home Manager (see ./home.nix).
    environment.systemPackages = with pkgs; [
      curl
      wget
      vim
      unzip
      zip
      lsof
      pciutils
    ];
  };
}
