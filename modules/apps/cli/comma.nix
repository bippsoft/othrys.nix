# modules/apps/cli/comma.nix
# Comma and nix-index-database for command-not-found
{
  config,
  lib,
  pkgs,
  othrysInputs,
  ...
}: let
  cfg = config.othrys.apps.comma;
in {
  options.othrys.apps.comma = {
    enable = lib.mkEnableOption "Comma and nix-index-database";
  };

  config = lib.mkIf cfg.enable {
    # The Home Manager module below installs both tools wrapped with the
    # prebuilt database. The bare packages have no database until nix-index
    # has been run by hand, so they go on the system path only on a host
    # whose user Home Manager does not manage, where they are the only copy.
    # Beside the wrapped ones they would be a second comma that fails for
    # root.
    environment.systemPackages = lib.mkIf (!config.othrys.system.users.homeManaged) (with pkgs; [
      comma
      nix-index
    ]);

    # The imported module turns programs.nix-index on, which is what installs
    # the command-not-found handler in the user's shells.
    #
    # It comes from the nix-index-database flake this library locks, handed
    # in by flake/modules.nix. There is no package option to set here, since
    # the module carries the database itself. A consumer who wants another
    # revision makes this library's input follow their own, with
    # `inputs.othrys.inputs.nix-index-database.follows = "nix-index-database"`.
    othrys.internal.homeConfig."apps.comma" = {
      imports = [
        othrysInputs.nix-index-database.homeModules.nix-index
      ];

      programs.nix-index-database.comma.enable = true;
    };
  };
}
