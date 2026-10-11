# modules/apps/gui/vscode/languages/lua.nix
# Lua: extensions for the shared toolchain (othrys.apps.languages.lua)
#
# sumneko.lua formats through the language server and has no setting for an
# external formatter, so the registry formatter reaches nixvim and the PATH
# only.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.lua;
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        sumneko.lua
      ];
      # Without the path the extension runs the lua-language-server it
      # bundles.
      userSettings."Lua.misc.executablePath" = lib.mkIf (lang.server != null) (lib.getExe lang.server);
    };
  };
}
