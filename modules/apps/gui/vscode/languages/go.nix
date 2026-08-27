# modules/apps/gui/vscode/languages/go.nix
# Go: extensions for the shared toolchain (othrys.apps.languages.go).
{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.languages.go.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        golang.go
      ];
      # Use the shared gopls from PATH instead of asking the extension to
      # download its own tools.
      userSettings."go.toolsManagement.checkForUpdates" = "off";
    };
  };
}
