# modules/apps/cli/nixvim/languages/typescript.nix
# TypeScript: wires the shared toolchain (othrys.apps.languages.typescript)
# into nixvim. JSON and YAML are languages of their own, in json.nix and
# yaml.nix.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.typescript;
  conform = import ./conform.nix {inherit lib;};
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.ts_ls = lib.mkIf (lang.server != null) {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings = conform ["javascript" "typescript"] lang.formatter;

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        javascript
        typescript
      ];
    };
  };
}
