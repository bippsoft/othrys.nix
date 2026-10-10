# modules/apps/cli/nixvim/languages/json.nix
# JSON: wires the shared toolchain (othrys.apps.languages.json) into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.json;
  conform = import ./conform.nix {inherit lib;};
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.jsonls = lib.mkIf (lang.server != null) {
        enable = true;
        package = lang.server;
        # The default package holds four servers and names no main program,
        # so the command spells out which binary is the JSON one.
        config.cmd = [(lib.getExe' lang.server "vscode-json-language-server") "--stdio"];
      };

      plugins.conform-nvim.settings = conform ["json" "jsonc"] lang.formatter;

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        json
      ];
    };
  };
}
