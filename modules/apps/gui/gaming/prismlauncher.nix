# modules/apps/gui/gaming/prismlauncher.nix
# PrismLauncher Minecraft launcher with persistence
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.gaming.prismlauncher;
in {
  options.othrys.apps.gaming.prismlauncher = {
    enable = lib.mkEnableOption "PrismLauncher Minecraft launcher";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.prismlauncher;
      defaultText = lib.literalExpression "pkgs.prismlauncher";
      description = "PrismLauncher package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Instances, settings and accounts.json, which holds the Microsoft refresh
    # tokens, so the directory is 0700.
    othrys.internal.persist."apps.gaming.prismlauncher" = {
      user.directories = [
        {
          directory = ".local/share/PrismLauncher";
          mode = "0700";
        }
      ];
    };

    # Install PrismLauncher for the user via home-manager
    othrys.internal.homeConfig."apps.gaming.prismlauncher" = {
      home.packages = [cfg.package];
    };
  };
}
