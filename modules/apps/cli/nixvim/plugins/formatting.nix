# modules/apps/cli/nixvim/plugins/formatting.nix
# Format-on-save via conform.nvim, with per-language formatters in languages/
_: {
  programs.nixvim = {
    plugins.conform-nvim = {
      enable = true;
      settings = {
        # Per-language formatters_by_ft configured by language modules
        # in nixvim/languages/*.nix, gated by othrys.apps.languages.*.enable
        format_on_save = {
          lsp_fallback = true;
          async = false;
          timeout_ms = 1000;
        };
      };
    };

    # Format keybinding
    keymaps = [
      {
        mode = ["n" "v"];
        key = "<leader>fm";
        action = "<cmd>lua require('conform').format()<CR>";
        options = {
          desc = "Format buffer/selection";
          silent = true;
        };
      }
    ];
  };
}
