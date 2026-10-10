# modules/apps/gui/vesktop.nix
# Vesktop - Discord client with Wayland support
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.vesktop;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.vesktop = {
    enable = lib.mkEnableOption "Vesktop Discord client";

    settings = lib.mkOption {
      # The value is written with builtins.toJSON, so it is held to what JSON
      # can carry. A function or a package is refused here by name, where
      # toJSON would abort or write a store path into the file.
      type = lib.types.attrsOf (pkgs.formats.json {}).type;
      default = {};
      description = "Extra Vesktop settings.json values, merged over the module defaults (override any default by re-declaring its key). Any JSON value is accepted.";
      example = lib.literalExpression "{ startMinimized = true; }";
    };
  };

  config = lib.mkIf cfg.enable {
    # sessionData under this directory holds the Discord token.
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        {
          directory = ".config/vesktop";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.vesktop" = {
      home.packages = with pkgs; [vesktop];

      xdg.configFile."vesktop/settings.json".text = builtins.toJSON ({
          enableHardwareAcceleration = true;
          useQuickCss = true;
          arRPC = true;
          minimizeToTray = true;
          startMinimized = false;
        }
        // cfg.settings);
    };
  };
}
