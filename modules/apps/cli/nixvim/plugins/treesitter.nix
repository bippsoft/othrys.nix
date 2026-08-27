# modules/apps/cli/nixvim/plugins/treesitter.nix
# Treesitter highlighting, indentation and incremental selection
{pkgs, ...}: {
  programs.nixvim = {
    plugins.treesitter = {
      enable = true;

      settings = {
        highlight = {
          enable = true;
          additional_vim_regex_highlighting = false;
        };

        indent = {
          enable = true;
        };

        incremental_selection = {
          enable = true;
          keymaps = {
            init_selection = "gnn";
            node_incremental = "grn";
            scope_incremental = "grc";
            node_decremental = "grm";
          };
        };
      };

      # Base grammars always available. Language-specific grammars are added
      # by nixvim/languages/*.nix, gated by othrys.apps.languages.*.enable.
      grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        markdown
        markdown_inline
        toml
        html
        css
        regex
        vim
        vimdoc
      ];
    };
  };
}
