# modules/apps/gui/discord.nix
# Discord, the official desktop client (a prebuilt Electron binary)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.discord;
in {
  options.othrys.apps.discord = {
    enable = lib.mkEnableOption "Discord official client";
  };

  config = lib.mkIf cfg.enable {
    # nixpkgs ships discord for some platforms only. Without this the host fails
    # deep inside the package set with a message that does not name the option.
    assertions = [
      {
        assertion = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.discord;
        message = "othrys.apps.discord: nixpkgs does not provide discord for ${pkgs.stdenv.hostPlatform.system}. Turn the module off on this host.";
      }
    ];

    # The Electron local storage under this directory holds the session token.
    othrys.internal.persist."apps.discord" = {
      user.directories = [
        {
          directory = ".config/discord";
          mode = "0700";
        }
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
