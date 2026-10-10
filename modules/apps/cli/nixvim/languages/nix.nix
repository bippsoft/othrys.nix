# modules/apps/cli/nixvim/languages/nix.nix
# Nix: wires the shared toolchain (othrys.apps.languages.nix) into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.nix;
  conform = import ./conform.nix {inherit lib;};
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.nil_ls = lib.mkIf (lang.server != null) {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings = conform ["nix"] lang.formatter;

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        nix
      ];
    };
  };
}
