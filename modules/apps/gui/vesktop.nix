# modules/apps/gui/vesktop.nix
# Vesktop - Discord client with Wayland support
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.vesktop;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.vesktop = {
    enable = lib.mkEnableOption "Vesktop Discord client";

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra Vesktop settings.json values, merged over the module defaults (override any default by re-declaring its key).";
      example = lib.literalExpression "{ startMinimized = true; }";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for Discord/Vesktop data
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/vesktop"
      ];
    };

    home-manager.users.${username} = {
      home.packages = with pkgs; [vesktop];

      xdg.configFile."vesktop/settings.json".text = builtins.toJSON ({
          enableHardwareAcceleration = true;
          useQuickCss = true;
          arRPC = true;
          minimizeToTray = true;
          startMinimized = false;
        }
        // cfg.settings);

      xdg.configFile."discord/settings.json".text = builtins.toJSON {
        SKIP_HOST_UPDATE = true;
      };
    };
  };
}
