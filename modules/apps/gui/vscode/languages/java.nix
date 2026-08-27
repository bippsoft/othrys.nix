# modules/apps/gui/vscode/languages/java.nix
# Java: extensions for the shared toolchain (othrys.apps.languages.java).
# redhat.java bundles jdtls, while jdk/maven/gradle come from the language module.
{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.languages.java.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        redhat.java
        vscjava.vscode-java-debug
      ];
    };
  };
}
