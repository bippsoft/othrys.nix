# modules/apps/gui/vscode/languages/go.nix
# Go: extensions for the shared toolchain (othrys.apps.languages.go).
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.go;
  # The go package's main program is the toolchain driver, and gofmt sits
  # beside it. Any other formatter is its own main program.
  formatter =
    if (lang.formatter.meta.mainProgram or "") == "go"
    then lib.getExe' lang.formatter "gofmt"
    else lib.getExe lang.formatter;
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        golang.go
      ];
      userSettings = {
        # The tools are store paths, so the extension has nothing to download
        # or update.
        "go.toolsManagement.checkForUpdates" = "off";
        "go.formatTool" = "custom";
        "go.alternateTools" = lib.mkMerge [
          {customFormatter = formatter;}
          (lib.mkIf (lang.server != null) {gopls = lib.getExe lang.server;})
        ];
      };
    };
  };
}
