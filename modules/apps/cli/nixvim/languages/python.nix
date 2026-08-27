# modules/apps/cli/nixvim/languages/python.nix
# Python: wires the shared toolchain (othrys.apps.languages.python) into
# nixvim. basedpyright for types/completion, ruff for formatting, the same
# canonical stack vscode uses.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.python;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.basedpyright = {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings.formatters_by_ft.python = ["ruff_format"];

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        python
      ];
    };
  };
}
