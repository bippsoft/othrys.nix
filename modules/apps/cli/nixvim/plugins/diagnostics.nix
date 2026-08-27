# modules/apps/cli/nixvim/plugins/diagnostics.nix
# Diagnostics: the trouble list and todo-comments highlighting
{
  lib,
  osConfig,
  ...
}: let
  # Todo-comment highlight fallbacks, using the Stylix scheme when the host themes
  # itself, neutral literals otherwise (lazy branch, no stylix dependency).
  todoColors =
    if osConfig.othrys.system.stylix.enable
    then
      with osConfig.lib.stylix.colors.withHashtag; {
        error = base08;
        warning = base0A;
        info = base0D;
        hint = base0C;
        default = base0E;
        test = base0B;
      }
    else {
      error = "#DC2626";
      warning = "#FBBF24";
      info = "#2563EB";
      hint = "#10B981";
      default = "#7C3AED";
      test = "#FF00FF";
    };
in {
  config = lib.mkIf osConfig.othrys.apps.nixvim.presets.diagnostics {
    programs.nixvim = {
      # Trouble.nvim - Advanced diagnostics UI
      plugins.trouble = {
        enable = true;

        settings = {
          position = "bottom";
          height = 10;
          width = 50;
        };
      };

      # Todo-Comments - Task management
      plugins.todo-comments = {
        enable = true;

        settings = {
          signs = true;
          sign_priority = 8;
          keywords = {
            FIX = {
              icon = " ";
              color = "error";
              alt = ["FIXME" "BUG" "FIXIT" "ISSUE"];
            };
            TODO = {
              icon = " ";
              color = "info";
            };
            HACK = {
              icon = " ";
              color = "warning";
            };
            WARN = {
              icon = " ";
              color = "warning";
              alt = ["WARNING" "XXX"];
            };
            PERF = {
              icon = " ";
              color = "default";
              alt = ["OPTIM" "PERFORMANCE" "OPTIMIZE"];
            };
            NOTE = {
              icon = " ";
              color = "hint";
              alt = ["INFO"];
            };
            TEST = {
              icon = "⏲ ";
              color = "test";
              alt = ["TESTING" "PASSED" "FAILED"];
            };
          };
          gui_style = {
            fg = "NONE";
            bg = "BOLD";
          };
          merge_keywords = true;
          highlight = {
            multiline = true;
            multiline_pattern = "^.";
            multiline_context = 10;
            before = "";
            keyword = "wide";
            after = "fg";
            pattern = "[[.*<(KEYWORDS)\\s*:]]";
            comments_only = true;
            max_line_len = 400;
            exclude = [];
          };
          # Highlight-group first, and the hex fallback follows the host theme
          # (see todoColors at the top of this file).
          colors = {
            error = ["DiagnosticError" "ErrorMsg" todoColors.error];
            warning = ["DiagnosticWarn" "WarningMsg" todoColors.warning];
            info = ["DiagnosticInfo" todoColors.info];
            hint = ["DiagnosticHint" todoColors.hint];
            default = ["Identifier" todoColors.default];
            test = ["Identifier" todoColors.test];
          };
          search = {
            command = "rg";
            args = [
              "--color=never"
              "--no-heading"
              "--with-filename"
              "--line-number"
              "--column"
            ];
            pattern = "\\b(KEYWORDS):";
          };
        };
      };

      # Diagnostic keybindings
      keymaps = [
        {
          mode = "n";
          key = "<leader>do";
          action = "<cmd>lua vim.diagnostic.open_float()<CR>";
          options = {
            desc = "Open diagnostic float";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>dq";
          action = "<cmd>lua vim.diagnostic.setqflist()<CR>";
          options = {
            desc = "Diagnostics to quickfix";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>dn";
          action = "<cmd>lua vim.diagnostic.goto_next()<CR>";
          options = {
            desc = "Next diagnostic";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>dp";
          action = "<cmd>lua vim.diagnostic.goto_prev()<CR>";
          options = {
            desc = "Previous diagnostic";
            silent = true;
          };
        }

        # Trouble.nvim keybindings
        {
          mode = "n";
          key = "<leader>xx";
          action = "<cmd>Trouble diagnostics toggle<CR>";
          options = {
            desc = "Trouble: Toggle diagnostics";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>xX";
          action = "<cmd>Trouble diagnostics toggle filter.buf=0<CR>";
          options = {
            desc = "Trouble: Buffer diagnostics";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>xl";
          action = "<cmd>Trouble loclist toggle<CR>";
          options = {
            desc = "Trouble: Location list";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>xq";
          action = "<cmd>Trouble qflist toggle<CR>";
          options = {
            desc = "Trouble: Quickfix list";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>xr";
          action = "<cmd>Trouble lsp_references toggle<CR>";
          options = {
            desc = "Trouble: LSP references";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>xd";
          action = "<cmd>Trouble lsp_definitions toggle<CR>";
          options = {
            desc = "Trouble: LSP definitions";
            silent = true;
          };
        }

        # Todo-Comments keybindings
        {
          mode = "n";
          key = "<leader>xt";
          action = "<cmd>TodoTrouble<CR>";
          options = {
            desc = "Todo: Show in Trouble";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>xT";
          # snacks.picker when the picker preset provides it, otherwise the
          # quickfix list, which todo-comments always ships.
          action =
            if osConfig.othrys.apps.nixvim.presets.picker
            then "<cmd>lua Snacks.picker.todo_comments()<CR>"
            else "<cmd>TodoQuickFix<CR>";
          options = {
            desc = "Todo: list all";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "]t";
          action = "<cmd>lua require('todo-comments').jump_next()<CR>";
          options = {
            desc = "Next todo comment";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "[t";
          action = "<cmd>lua require('todo-comments').jump_prev()<CR>";
          options = {
            desc = "Previous todo comment";
            silent = true;
          };
        }
      ];
    };
  };
}
