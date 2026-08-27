# modules/apps/gui/gaming/prismlauncher.nix
# PrismLauncher Minecraft launcher with persistence
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.gaming.prismlauncher;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.gaming.prismlauncher = {
    enable = lib.mkEnableOption "PrismLauncher Minecraft launcher";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.prismlauncher;
      description = "PrismLauncher package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for Minecraft instances, accounts, settings
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".local/share/PrismLauncher"
      ];
    };

    # Install PrismLauncher for the user via home-manager
    home-manager.users.${username} = {
      home.packages = [cfg.package];
    };
  };
}
