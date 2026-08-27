# modules/apps/cli/nixvim/plugins/utilities.nix
# Core editing utilities, plus session management behind presets.sessions.
{
  lib,
  osConfig,
  ...
}: {
  config = lib.mkMerge [
    {
      programs.nixvim = {
        plugins.indent-blankline.enable = true;
        plugins.web-devicons.enable = true;

        # Better quickfix list
        plugins.nvim-bqf = {
          enable = true;
          settings = {
            auto_enable = true;
            preview = {
              win_height = 12;
              win_vheight = 12;
              delay_syntax = 80;
              border = ["┏" "━" "┓" "┃" "┛" "━" "┗" "┃"];
              show_title = false;
              should_preview_cb = null;
            };
            func_map = {
              vsplit = "";
              ptogglemode = "z,";
              stoggleup = "";
            };
            filter = {
              fzf = {
                action_for = {
                  "ctrl-s" = "split";
                };
                extra_opts = ["--bind" "ctrl-o:toggle-all" "--prompt" "> "];
              };
            };
          };
        };

        # Better buffer deletion
        plugins.bufdelete = {
          enable = true;
        };

        # Highlight color codes
        plugins.colorizer = {
          enable = true;
        };

        keymaps = [
          # Buffer deletion keybinding
          {
            mode = "n";
            key = "<leader>bd";
            action = "<cmd>Bdelete<CR>";
            options = {
              desc = "Delete buffer (keep window)";
              silent = true;
            };
          }
        ];
      };
    }
    (lib.mkIf osConfig.othrys.apps.nixvim.presets.sessions {
      programs.nixvim = {
        # Session Management
        plugins.persistence = {
          enable = true;
          # Snacks explorer buffers are excluded via autocmd (see autocmds.nix)
          # to prevent "Buffer with this name already exists" errors on toggle
        };

        keymaps = [
          {
            mode = "n";
            key = "<leader>qs";
            action = "<cmd>lua require('persistence').load()<CR>";
            options = {
              desc = "Restore session";
              silent = true;
            };
          }
          {
            mode = "n";
            key = "<leader>ql";
            action = "<cmd>lua require('persistence').load({ last = true })<CR>";
            options = {
              desc = "Restore last session";
              silent = true;
            };
          }
          {
            mode = "n";
            key = "<leader>qd";
            action = "<cmd>lua require('persistence').stop()<CR>";
            options = {
              desc = "Don't save session";
              silent = true;
            };
          }
        ];
      };
    })
  ];
}
