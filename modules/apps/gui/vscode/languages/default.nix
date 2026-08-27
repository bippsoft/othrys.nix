# modules/apps/gui/vscode/languages/default.nix
# Language-specific VS Code extension imports
{
  imports = [
    ./nix.nix
    ./python.nix
    ./rust.nix
    ./typescript.nix
    ./go.nix
    ./lua.nix
    ./bash.nix
    ./java.nix
  ];
}
