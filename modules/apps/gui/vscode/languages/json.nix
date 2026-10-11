# modules/apps/gui/vscode/languages/json.nix
# JSON: settings for the shared toolchain (othrys.apps.languages.json)
#
# The editor's built-in JSON support is the same server the registry holds and
# takes no external path, so only the formatter is wired, through
# prettier.nix.
{
  osConfig,
  lib,
  ...
}: let
  lang = osConfig.othrys.apps.languages.json;
  usesPrettier = (lang.formatter.meta.mainProgram or "") == "prettier";
  prettier = lib.mkIf usesPrettier {"editor.defaultFormatter" = "esbenp.prettier-vscode";};
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default.userSettings = {
      "[json]" = prettier;
      "[jsonc]" = prettier;
    };
  };
}
