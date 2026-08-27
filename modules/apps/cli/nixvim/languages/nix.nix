# modules/apps/cli/nixvim/languages/nix.nix
# Nix: wires the shared toolchain (othrys.apps.languages.nix) into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.nix;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.nil_ls = {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings.formatters_by_ft.nix = ["alejandra"];

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        nix
      ];
    };
  };
}
