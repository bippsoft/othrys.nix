# modules/apps/cli/nixvim/languages/rust.nix
# Rust: wires the shared toolchain (othrys.apps.languages.rust) into nixvim.
# cargo/rustc come from the project (nix develop), not the editor. The native
# lsp namespace never installs a toolchain of its own, so this needs no opt-out.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.rust;
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.rust_analyzer = {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings.formatters_by_ft.rust = ["rustfmt"];

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        rust
      ];
    };
  };
}
