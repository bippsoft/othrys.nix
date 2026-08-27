# modules/apps/cli/nixvim/plugins/navigation.nix
# File explorer via snacks.explorer (presets.fileTree). Backed by the picker,
# so it inherits the same fuzzy matching and keymaps.
{
  lib,
  osConfig,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.nixvim.presets.fileTree {
    programs.nixvim = {
      plugins.snacks = {
        enable = true;
        settings.explorer.enabled = true;
      };

      keymaps = [
        {
          mode = "n";
          key = "<leader>e";
          action = "<cmd>lua Snacks.explorer()<CR>";
          options = {
            desc = "Toggle file explorer";
            silent = true;
          };
        }
      ];
    };
  };
}
