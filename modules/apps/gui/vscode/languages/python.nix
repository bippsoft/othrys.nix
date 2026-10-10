# modules/apps/gui/vscode/languages/python.nix
# Python: extensions for the shared toolchain (othrys.apps.languages.python).
# basedpyright for types/completion, ruff for lint/format, the same
# canonical stack nixvim uses. detachhead.basedpyright has no setting for an
# external server binary, so it runs the one it bundles.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.python;
  usesRuff = (lang.formatter.meta.mainProgram or "") == "ruff";
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        detachhead.basedpyright
        charliermarsh.ruff
      ];
      userSettings = lib.mkMerge [
        {
          # basedpyright provides the language server, so disable ms-python's
          # default (Pylance, which is proprietary and won't run in VSCodium).
          "python.languageServer" = "None";
        }
        # The ruff extension can only drive ruff. A host that replaces the
        # formatter with another tool keeps the extension for linting and
        # chooses its own default formatter.
        (lib.mkIf usesRuff {
          "ruff.path" = [(lib.getExe lang.formatter)];
          "[python]"."editor.defaultFormatter" = "charliermarsh.ruff";
        })
      ];
    };
  };
}
