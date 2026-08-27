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
      userSettings = {
        "nix.enableLanguageServer" = true;
        # The SAME server binary the whole host uses (previously a bare "nil"
        # that was never installed anywhere).
        "nix.serverPath" = lib.getExe lang.server;
        "nix.formatterPath" = lib.getExe lang.formatter;
      };
    };
  };
}
