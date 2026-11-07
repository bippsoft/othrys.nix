# modules/system/users.darwin.nix
# The nix-darwin implementation of othrys.system.users
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

  options.othrys.system.users.uid = lib.mkOption {
    type = lib.types.nullOr lib.types.int;
    default = null;
    example = 502;
    description = ''
      UID of the primary user, on nix-darwin only. Null leaves the account to
      macOS. Set, it puts the user in `users.knownUsers`, so nix-darwin owns
      the account, creates it when it is missing and applies `defaultShell`
      as its login shell. The administrator account macOS created at setup,
      usually uid 501, keeps null, since nix-darwin must not manage it.
    '';
  };

  config = lib.mkIf config.othrys.system.users.enable {
    # macOS creates the admin account at setup, and nix-darwin manages only
    # the users named in users.knownUsers, which its documentation says must
    # not hold the admin. Left out of that list, the entry below records the
    # home directory that Home Manager and system.primaryUserHome read, and
    # changes nothing about the account itself.
    users.users.${username} = lib.mkMerge [
      {home = lib.mkDefault "/Users/${username}";}

      # nix-darwin applies a login shell only to a user it owns, and owning
      # one takes a uid. A host that states the uid hands the account to
      # nix-darwin, which may then create it and rewrites its shell on every
      # activation.
      (lib.mkIf (cfg.uid != null) {
        inherit (cfg) uid;
        # nix-darwin creates a known user hidden from the login window and
        # without a home directory unless told otherwise.
        isHidden = false;
        createHome = true;
        # nix-darwin warns on every rebuild about bash without readline, so
        # the default bash becomes the interactive build.
        shell =
          if cfg.defaultShell == pkgs.bash
          then pkgs.bashInteractive
          else cfg.defaultShell;
      })
    ];

    users.knownUsers = lib.mkIf (cfg.uid != null) [username];

    # The user that options which once applied to whoever ran darwin-rebuild
    # now apply to, such as system.defaults and Homebrew.
    system.primaryUser = username;

    # The essential set of users.nixos.nix, less pciutils, which reads the
    # Linux sysfs and has no PCI bus to list on macOS.
    environment.systemPackages = with pkgs; [
      curl
      wget
      vim
      unzip
      zip
      lsof
    ];
  };
}
