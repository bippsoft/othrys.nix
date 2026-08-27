# modules/apps/cli/nixvim/plugins/editor.nix
# Editing behaviour: autopairs, surround, comment toggling, sleuth
_: {
  programs.nixvim = {
    # Nvim-Autopairs - Enhanced with treesitter
    plugins.nvim-autopairs.enable = true;

    # Configure autopairs via extraConfigLua to avoid Nix escaping issues
    extraConfigLua = ''
      require('nvim-autopairs').setup({
        check_ts = true,
        ts_config = {
          lua = { 'string', 'source' },
          javascript = { 'string', 'template_string' },
          java = { 'string', 'character' }
        },
        disable_filetype = { 'snacks_picker_input', 'spectre_panel' },
        fast_wrap = {
          map = '<M-e>',
          chars = { '{', '[', '(', '"', "'" },
          pattern = [=[[%'%"%)%>%]%)%}%,]]=],
          offset = 0,
          end_key = '$',
          keys = 'qwertyuiopzxcvbnmasdfghjkl',
          check_comma = true,
          highlight = 'PmenuSel',
          highlight_grey = 'LineNr'
        }
      })
    '';

    plugins.comment.enable = true;
    plugins.vim-surround.enable = true;
    plugins.sleuth.enable = true;
  };
}
