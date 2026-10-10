# modules/apps/gui/vscode/languages/bash.nix
# Bash: extensions for the shared toolchain (othrys.apps.languages.bash).
# bash-ide-vscode bundles bash-language-server and has no setting for an
# external one, so the registry server reaches nixvim and the PATH only.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.bash;
  # shellcheck is an extra tool in the registry and not the formatter or the
  # server, so it is found by its executable name. A host that drops it from
  # extraTools gets neither setting, and both extensions fall back to the PATH.
  shellcheck = lib.findFirst (tool: (tool.meta.mainProgram or "") == "shellcheck") null lang.extraTools;
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        mads-hartmann.bash-ide-vscode
        timonwong.shellcheck
      ];
      userSettings = lib.mkMerge [
        {"bashIde.shfmt.path" = lib.getExe lang.formatter;}
        (lib.mkIf (shellcheck != null) {
          "shellcheck.executablePath" = lib.getExe shellcheck;
          "bashIde.shellcheckPath" = lib.getExe shellcheck;
        })
      ];
    };
  };
}
