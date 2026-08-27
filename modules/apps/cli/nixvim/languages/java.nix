# modules/apps/cli/nixvim/languages/java.nix
# Java: wires the shared toolchain (othrys.apps.languages.java) into nixvim.
# Deliberately no Java LSP in neovim, since jdtls integration is heavyweight and
# vscode (redhat.java) covers the IDE use case, and nixvim gets formatting and
# syntax. jdk/maven/gradle come from the language module's extraTools.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.java;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      plugins.conform-nvim.settings.formatters_by_ft.java = ["google-java-format"];

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        java
      ];
    };
  };
}
