# modules/apps/cli/nixvim/languages/bash.nix
# Bash: wires the shared toolchain (othrys.apps.languages.bash) into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.bash;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.bashls = {
        enable = true;
        package = lang.server;
      };

      # Formatter binary comes from the shared toolchain on PATH.
      plugins.conform-nvim.settings.formatters_by_ft.sh = ["shfmt"];

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        bash
      ];
    };
  };
}
