# modules/apps/gui/vscode/languages/typescript.nix
# TypeScript: extensions for the shared toolchain
# (othrys.apps.languages.typescript).
{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf osConfig.othrys.apps.languages.typescript.enable {
    programs.vscodium.profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        esbenp.prettier-vscode
      ];
    };
  };
}
