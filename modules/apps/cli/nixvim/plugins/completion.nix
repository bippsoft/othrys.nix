# modules/apps/cli/nixvim/plugins/completion.nix
# Completion via blink.cmp. Snippets stay on luasnip (see snippets.nix), which
# blink drives through its luasnip preset, so friendly-snippets and the
# existing <C-k>/<C-j> jump bindings keep working unchanged.
_: {
  programs.nixvim = {
    plugins.blink-cmp = {
      enable = true;

      settings = {
        snippets.preset = "luasnip";

        appearance.nerd_font_variant = "mono";

        sources.default = ["lsp" "path" "snippets" "buffer"];

        signature.enabled = true;

        completion = {
          documentation = {
            auto_show = true;
            auto_show_delay_ms = 200;
            window.border = "rounded";
          };
          menu.border = "rounded";
          # blink replaces the old nvim-autopairs/cmp confirm_done hook.
          accept.auto_brackets.enabled = true;
        };

        # Built on the "enter" preset so <CR> accepts, with the nvim-cmp
        # bindings this config already used layered back on top.
        keymap = {
          preset = "enter";
          "<C-Space>" = ["show" "show_documentation" "hide_documentation"];
          "<C-d>" = ["scroll_documentation_up" "fallback"];
          "<C-f>" = ["scroll_documentation_down" "fallback"];
          "<Tab>" = ["select_next" "snippet_forward" "fallback"];
          "<S-Tab>" = ["select_prev" "snippet_backward" "fallback"];
        };
      };
    };
  };
}
