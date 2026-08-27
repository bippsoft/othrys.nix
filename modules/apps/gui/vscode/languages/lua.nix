# modules/apps/gui/vscode/languages/lua.nix
# Lua: extensions for the shared toolchain (othrys.apps.languages.lua).
{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.languages.lua.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        sumneko.lua
      ];
    };
  };
}
