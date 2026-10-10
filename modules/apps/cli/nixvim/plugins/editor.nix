# modules/apps/cli/nixvim/plugins/editor.nix
# Editing behaviour: autopairs, surround, comment toggling, sleuth
_: {
  programs.nixvim = {
    # nixvim renders `settings` into the plugin's one setup call. A second
    # setup in extraConfigLua would replace this table and register the
    # plugin's autocommands again.
    plugins.nvim-autopairs = {
      enable = true;
      settings = {
        check_ts = true;
        ts_config = {
          lua = ["string" "source"];
          javascript = ["string" "template_string"];
          java = ["string" "character"];
        };
        disable_filetype = ["snacks_picker_input" "spectre_panel"];
        fast_wrap = {
          map = "<M-e>";
          chars = ["{" "[" "(" "\"" "'"];
          # A Lua long string, written into the setup call as code.
          pattern.__raw = "[=[[%'%\"%)%>%]%)%}%,]]=]";
          offset = 0;
          end_key = "$";
          keys = "qwertyuiopzxcvbnmasdfghjkl";
          check_comma = true;
          highlight = "PmenuSel";
          highlight_grey = "LineNr";
        };
      };
    };

    plugins.comment.enable = true;
    plugins.vim-surround.enable = true;
    plugins.sleuth.enable = true;
  };
}
