# modules/apps/gui/vscode/languages/bash.nix
# Bash: extensions for the shared toolchain (othrys.apps.languages.bash).
{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.languages.bash.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        mads-hartmann.bash-ide-vscode
        timonwong.shellcheck
      ];
      # shellcheck binary comes from the shared toolchain on PATH.
      userSettings."shellcheck.executablePath" = lib.getExe pkgs.shellcheck;
    };
  };
}
