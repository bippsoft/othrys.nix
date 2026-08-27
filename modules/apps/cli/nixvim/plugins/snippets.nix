# modules/apps/cli/nixvim/plugins/snippets.nix
# Snippet expansion via luasnip
{pkgs, ...}: {
  programs.nixvim = {
    # Snippets
    plugins.luasnip = {
      enable = true;

      settings = {
        history = true;
        updateevents = "TextChanged,TextChangedI";
        enable_autosnippets = true;
        ext_opts = null;
      };

      fromVscode = [
        {paths = "${pkgs.vimPlugins.friendly-snippets}";}
      ];
    };

    # Luasnip keybindings
    keymaps = [
      {
        mode = ["i" "s"];
        key = "<C-k>";
        action = "<cmd>lua require('luasnip').expand_or_jump()<CR>";
        options = {
          desc = "Expand or jump snippet";
          silent = true;
        };
      }
      {
        mode = ["i" "s"];
        key = "<C-j>";
        action = "<cmd>lua require('luasnip').jump(-1)<CR>";
        options = {
          desc = "Jump back in snippet";
          silent = true;
        };
      }
    ];
  };
}
