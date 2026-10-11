# modules/apps/gui/vscode/languages/prettier.nix
# Prettier: one extension and one module path for the languages that use it
#
# Those are the languages whose registry formatter is prettier, out of
# typescript, json and yaml.
#
# The extension loads prettier as a Node module, so the setting names the
# module directory inside the registry package. Left unset, the extension
# takes whichever prettier the open workspace carries in node_modules and
# falls back to its bundled copy. A language whose formatter was replaced
# with another tool is skipped here, and its own file then leaves the
# default formatter alone.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  languages = osConfig.othrys.apps.languages;
  usesPrettier = lang: lang.enable && (lang.formatter.meta.mainProgram or "") == "prettier";
  # The first enabled language in this order supplies the module, since the
  # extension takes a single path.
  formatters = map (lang: lang.formatter) (builtins.filter usesPrettier [
    languages.typescript
    languages.json
    languages.yaml
  ]);
in {
  config = lib.mkIf (formatters != []) {
    programs.vscodium.profiles.default = {
      extensions = [pkgs.vscode-extensions.esbenp.prettier-vscode];
      userSettings."prettier.prettierPath" = "${builtins.head formatters}/lib/node_modules/prettier";
    };
  };
}
