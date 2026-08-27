# modules/apps/gui/vscode/languages/python.nix
# Python: extensions for the shared toolchain (othrys.apps.languages.python).
# basedpyright for types/completion, ruff for lint/format, the same
# canonical stack nixvim uses.
{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.languages.python.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        detachhead.basedpyright
        charliermarsh.ruff
      ];
      userSettings = {
        # basedpyright provides the language server, so disable ms-python's
        # default (Pylance, which is proprietary and won't run in VSCodium).
        "python.languageServer" = "None";
        "[python]"."editor.defaultFormatter" = "charliermarsh.ruff";
      };
    };
  };
}
