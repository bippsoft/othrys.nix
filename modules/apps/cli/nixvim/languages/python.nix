# modules/apps/cli/nixvim/languages/python.nix
# Python: wires the shared toolchain (othrys.apps.languages.python) into nixvim
#
# basedpyright for types/completion, ruff for formatting, the same canonical
# stack vscode uses.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.python;
  conform = import ./conform.nix {inherit lib;};
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.basedpyright = lib.mkIf (lang.server != null) {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings = conform ["python"] lang.formatter;

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        python
      ];
    };
  };
}
