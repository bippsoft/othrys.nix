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
    environment.systemPackages = with pkgs; [
      comma
      nix-index
    ];

    othrys.internal.homeConfig."apps.comma" = {
      imports = [
        inputs.nix-index-database.homeModules.nix-index
      ];

      programs.nix-index-database.comma.enable = true;
    };
  };
}
