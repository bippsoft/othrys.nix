# modules/apps/cli/nixvim/plugins/lsp-base.nix
# Global LSP configuration applying to every language server. Individual
# servers are enabled in the languages/*.nix modules.
#
# Uses nixvim's top-level `lsp` namespace, which drives neovim's native
# vim.lsp.config/vim.lsp.enable directly. nvim-lspconfig is still installed,
# but only as the source of the per-server definitions (see below), not as the
# configuration layer.
{pkgs, ...}: {
  programs.nixvim = {
    # The native lsp namespace drives vim.lsp.enable, which resolves a server
    # by looking up lsp/<name>.lua on the runtimepath. nvim-lspconfig is what
    # ships those definitions (cmd, filetypes, root markers). Without it
    # vim.lsp.enable has nothing to enable and no client ever attaches, so the
    # plugin is still required, purely as the definition source rather than as
    # the configuration wrapper it used to be.
    extraPlugins = [pkgs.vimPlugins.nvim-lspconfig];

    lsp = {
      # Both are native to vim.lsp and cost nothing when a server does not
      # advertise the capability.
      inlayHints.enable = true;
      codelens.enable = true;

      # Registered when a server attaches, so they are buffer-local. The old
      # `keymaps` list bound these globally, which meant gd and friends were
      # live in buffers that had no language server behind them.
      keymaps = [
        {
          key = "gd";
          lspBufAction = "definition";
          options.desc = "Go to definition";
        }
        {
          key = "gD";
          lspBufAction = "declaration";
          options.desc = "Go to declaration";
        }
        {
          key = "gr";
          lspBufAction = "references";
          options.desc = "Go to references";
        }
        {
          key = "gi";
          lspBufAction = "implementation";
          options.desc = "Go to implementation";
        }
        {
          key = "<leader>D";
          lspBufAction = "type_definition";
          options.desc = "Type definition";
        }
        {
          key = "<leader>rn";
          lspBufAction = "rename";
          options.desc = "Rename";
        }
        {
          key = "<leader>ca";
          lspBufAction = "code_action";
          options.desc = "Code action";
        }
        {
          key = "K";
          action = "<cmd>lua vim.lsp.buf.hover({ border = 'rounded', max_width = 80 })<CR>";
          options = {
            desc = "Hover documentation";
            silent = true;
          };
        }
        {
          key = "<leader>wa";
          lspBufAction = "add_workspace_folder";
          options.desc = "Add workspace folder";
        }
        {
          key = "<leader>wr";
          lspBufAction = "remove_workspace_folder";
          options.desc = "Remove workspace folder";
        }
        {
          key = "<leader>wl";
          action = "<cmd>lua print(vim.inspect(vim.lsp.buf.list_workspace_folders()))<CR>";
          options = {
            desc = "List workspace folders";
            silent = true;
          };
        }
      ];
    };

    # Diagnostic presentation. nixvim exposes no typed option for this, so it
    # stays as a vim.diagnostic.config call.
    extraConfigLua = ''
      local signs = { Error = "󰅚 ", Warn = "󰀪 ", Hint = "󰌶 ", Info = "󰋼 " }
      for type, icon in pairs(signs) do
        local hl = "DiagnosticSign" .. type
        vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
      end

      vim.diagnostic.config({
        signs = true,
        underline = true,
        update_in_insert = false,
        virtual_text = {
          prefix = "●",
          spacing = 4,
        },
        severity_sort = true,
        float = {
          focusable = true,
          style = "minimal",
          border = "rounded",
          source = true,
          header = "",
          prefix = "",
        },
      })
    '';
  };
}
