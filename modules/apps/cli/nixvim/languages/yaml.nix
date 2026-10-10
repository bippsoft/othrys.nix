# modules/apps/cli/nixvim/languages/yaml.nix
# YAML: wires the shared toolchain (othrys.apps.languages.yaml) into nixvim.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.yaml;
  conform = import ./conform.nix {inherit lib;};
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.yamlls = lib.mkIf (lang.server != null) {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings = conform ["yaml"] lang.formatter;

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        yaml
      ];
    };
  };
}
