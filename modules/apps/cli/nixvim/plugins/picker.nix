# modules/apps/cli/nixvim/plugins/picker.nix
# Fuzzy finding via snacks.picker (presets.picker).
{
  lib,
  osConfig,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.nixvim.presets.picker {
    programs.nixvim = {
      plugins.snacks = {
        enable = true;
        settings.picker.enabled = true;
      };

      keymaps = [
        {
          mode = "n";
          key = "<leader>ff";
          action = "<cmd>lua Snacks.picker.files()<CR>";
          options = {
            desc = "Find files";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>fg";
          action = "<cmd>lua Snacks.picker.grep()<CR>";
          options = {
            desc = "Live grep";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>fb";
          action = "<cmd>lua Snacks.picker.buffers()<CR>";
          options = {
            desc = "Find buffers";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>fh";
          action = "<cmd>lua Snacks.picker.help()<CR>";
          options = {
            desc = "Help tags";
            silent = true;
          };
        }
        {
          mode = "n";
          key = "<leader>fr";
          action = "<cmd>lua Snacks.picker.recent()<CR>";
          options = {
            desc = "Recent files";
            silent = true;
          };
        }
      ];
    };
  };
}
