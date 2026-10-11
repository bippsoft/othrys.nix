# modules/apps/gui/vscode/languages/default.nix
# Language-specific VSCodium extension imports
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
    ./json.nix
    ./yaml.nix
    ./prettier.nix
  ];
}
