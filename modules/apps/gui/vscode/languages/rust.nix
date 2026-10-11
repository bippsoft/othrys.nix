# modules/apps/gui/vscode/languages/rust.nix
# Rust: extensions for the shared toolchain (othrys.apps.languages.rust)
#
# rust-analyzer formats by running the rustfmt it finds on the PATH, which is
# where the registry formatter is installed.
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
      # A null server is a legal registry value, and getExe on null aborts
      # evaluation with no assertion able to catch it. Without the path the
      # extension runs the rust-analyzer it bundles.
      userSettings."rust-analyzer.server.path" = lib.mkIf (lang.server != null) (lib.getExe lang.server);
    };
  };
}
