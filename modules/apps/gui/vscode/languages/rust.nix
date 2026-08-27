# modules/apps/gui/vscode/languages/rust.nix
# Rust: extensions for the shared toolchain (othrys.apps.languages.rust).
{
  osConfig,
  lib,
  pkgs,
  ...
}: let
  lang = osConfig.othrys.apps.languages.rust;
in {
  config = lib.mkIf lang.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        rust-lang.rust-analyzer
      ];
      # The SAME rust-analyzer binary the whole host uses.
      userSettings."rust-analyzer.server.path" = lib.getExe lang.server;
    };
  };
}
