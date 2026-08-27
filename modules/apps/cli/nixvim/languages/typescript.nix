# modules/apps/cli/nixvim/languages/typescript.nix
# TypeScript: wires the shared toolchain (othrys.apps.languages.typescript)
# into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.typescript;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.ts_ls = {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings.formatters_by_ft = {
        javascript = ["prettier"];
        typescript = ["prettier"];
        json = ["prettier"];
        yaml = ["prettier"];
      };

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        javascript
        typescript
        json
        yaml
      ];
    };
  };
}
