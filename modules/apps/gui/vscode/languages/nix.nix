# modules/apps/gui/vscode/languages/nix.nix
# Nix: extensions for the shared toolchain (othrys.apps.languages.nix).
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.nix;
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
      ];
      # A null server is a legal registry value, and getExe on null aborts
      # evaluation with no assertion able to catch it. The extension then
      # runs without a language server and keeps the formatter.
      userSettings = lib.mkMerge [
        {
          "nix.enableLanguageServer" = lang.server != null;
          "nix.formatterPath" = lib.getExe lang.formatter;
        }
        (lib.mkIf (lang.server != null) {
          "nix.serverPath" = lib.getExe lang.server;
        })
      ];
    };
  };
}
