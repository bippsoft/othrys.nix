# modules/apps/cli/nixvim/plugins/git.nix
# Git gutter signs via gitsigns
{
  lib,
  osConfig,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.nixvim.presets.git {
    programs.nixvim = {
      plugins.gitsigns.enable = true;
    };
  };
}
