# modules/apps/cli/nixvim/languages/lua.nix
# Lua: wires the shared toolchain (othrys.apps.languages.lua) into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.lua;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.lua_ls = {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings.formatters_by_ft.lua = ["stylua"];

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        lua
      ];
    };
  };
}
