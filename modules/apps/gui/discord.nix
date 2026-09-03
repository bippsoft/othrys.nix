# modules/apps/gui/discord.nix
# Discord, the official desktop client (a prebuilt Electron binary)
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.discord;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.discord = {
    enable = lib.mkEnableOption "Discord official client";
  };

  config = lib.mkIf cfg.enable {
    # Persistence for Discord data
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/discord"
      ];
    };

    othrys.internal.homeConfig."apps.discord" = {
      home.packages = with pkgs; [discord];

      # Let Nix manage the client, so skip Discord's own self-update prompt.
      xdg.configFile."discord/settings.json".text = builtins.toJSON {
        SKIP_HOST_UPDATE = true;
      };
    };
  };
}
