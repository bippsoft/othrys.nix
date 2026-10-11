# modules/apps/cli/comma.nix
# Comma and nix-index-database for command-not-found
{
  config,
  lib,
  pkgs,
  inputs,
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
    othrys.internal.homeConfig."apps.comma" = {
      imports = [
        inputs.nix-index-database.homeModules.nix-index
      ];

      programs.nix-index-database.comma.enable = true;
    };
  };
}
