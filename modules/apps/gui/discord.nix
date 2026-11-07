# modules/apps/gui/discord.nix
# Discord, the official desktop client (a prebuilt Electron binary)
{lib, ...}: {
  options.othrys.apps.discord = {
    enable = lib.mkEnableOption "Discord official client";
  };
}
