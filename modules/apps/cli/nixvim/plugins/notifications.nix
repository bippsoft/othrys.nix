# modules/apps/cli/nixvim/plugins/notifications.nix
# nvim-notify + dressing UI polish (presets.notifications).
{
  lib,
  osConfig,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.nixvim.presets.notifications {
    programs.nixvim = {
      plugins.notify = {
        enable = true;
        settings = {
          background_colour = "#000000";
          fps = 60;
          icons = {
            DEBUG = "";
            ERROR = "";
            INFO = "";
            TRACE = "✎";
            WARN = "";
          };
          level = 2;
          minimum_width = 50;
          render = "compact";
          stages = "fade_in_slide_out";
          timeout = 3000;
          top_down = true;
        };
      };

      plugins.dressing = {
        enable = true;
        settings = {
          input = {
            enabled = true;
            default_prompt = "Input:";
            border = "rounded";
            relative = "cursor";
            prefer_width = 40;
            width = null;
            max_width = [140 0.9];
            min_width = [20 0.2];
            win_options = {
              winblend = 10;
              wrap = false;
            };
          };
          select = {
            enabled = true;
            backend = ["builtin" "nui"];
            builtin = {
              border = "rounded";
              relative = "editor";
            };
          };
        };
      };

      extraConfigLua = ''
        -- Set notify as default notification handler
        vim.notify = require("notify")
      '';

      keymaps = [
        {
          mode = "n";
          key = "<leader>nd";
          action.__raw = "function() require('notify').dismiss({ silent = true, pending = true }) end";
          options = {
            desc = "Dismiss notifications";
            silent = true;
          };
        }
      ];
    };
  };
}
