# modules/apps/cli/nixvim/languages/go.nix
# Go: wires the shared toolchain (othrys.apps.languages.go) into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.go;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.gopls = {
        enable = true;
        package = lang.server;
      };

      # gofmt ships with the go toolchain installed by the language module.
      plugins.conform-nvim.settings.formatters_by_ft.go = ["gofmt"];

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        go
      ];
    };
  };
}
