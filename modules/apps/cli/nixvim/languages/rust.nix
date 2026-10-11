# modules/apps/cli/nixvim/languages/rust.nix
# Rust: wires the shared toolchain (othrys.apps.languages.rust) into nixvim
#
# cargo/rustc come from the project (nix develop), not the editor. The native
# lsp namespace never installs a toolchain of its own, so this needs no
# opt-out.
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.rust;
  conform = import ./conform.nix {inherit lib;};
in {
  config = lib.mkIf lang.enable {
    programs.nixvim = {
      lsp.servers.rust_analyzer = lib.mkIf (lang.server != null) {
        enable = true;
        package = lang.server;
      };

      plugins.conform-nvim.settings = conform ["rust"] lang.formatter;

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        rust
      ];
    };
  };
}
