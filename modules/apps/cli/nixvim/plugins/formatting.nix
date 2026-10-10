# modules/apps/cli/nixvim/plugins/formatting.nix
# Format-on-save via conform.nvim, with per-language formatters in languages/
_: {
  programs.nixvim = {
    plugins.conform-nvim = {
      enable = true;
      settings = {
        # formatters_by_ft and formatters come from nixvim/languages/*.nix,
        # gated by othrys.apps.languages.*.enable, and each formatter's
        # command is the registry package's store path.
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
