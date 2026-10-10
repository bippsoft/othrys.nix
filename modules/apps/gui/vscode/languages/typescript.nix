# modules/apps/gui/vscode/languages/typescript.nix
# TypeScript: settings for the shared toolchain
# (othrys.apps.languages.typescript). The editor's built-in TypeScript
# support provides the language service and takes no external server, so only
# the formatter is wired, through prettier.nix.
{
  osConfig,
  lib,
  ...
}: let
  lang = osConfig.othrys.apps.languages.typescript;
  usesPrettier = (lang.formatter.meta.mainProgram or "") == "prettier";
  prettier = lib.mkIf usesPrettier {"editor.defaultFormatter" = "esbenp.prettier-vscode";};
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default.userSettings = {
      "[javascript]" = prettier;
      "[typescript]" = prettier;
    };
  };
}
