# modules/apps/gui/vesktop.nixos.nix
# The NixOS implementation of othrys.apps.vesktop
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.vesktop;
in {
  imports = [./vesktop.nix];

  config = lib.mkIf cfg.enable {
    # sessionData under this directory holds the Discord token.
    othrys.internal.persist."apps.vesktop" = {
      user.directories = [
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
