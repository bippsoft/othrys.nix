# modules/apps/gui/vscode/languages/yaml.nix
# YAML: extension for the shared toolchain (othrys.apps.languages.yaml)
#
# redhat.vscode-yaml bundles yaml-language-server and has no setting for an
# external one, so the registry server reaches nixvim and the PATH only. The
# formatter is wired through prettier.nix.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.yaml;
  usesPrettier = (lang.formatter.meta.mainProgram or "") == "prettier";
  prettier = lib.mkIf usesPrettier {"editor.defaultFormatter" = "esbenp.prettier-vscode";};
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        redhat.vscode-yaml
      ];
      userSettings."[yaml]" = prettier;
    };
  };
}
