# modules/apps/cli/nixvim/plugins/statusline.nix
# Lualine statusline (presets.statusline).
{
  lib,
  osConfig,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.nixvim.presets.statusline {
    programs.nixvim.plugins.lualine = {
      enable = true;
      settings = {
        options = {
          theme = "auto";
          component_separators = "|";
          section_separators = "";
        };
      };
    };
  };
}
