# modules/apps/cli/nixvim/languages/default.nix
# Language-specific module imports
{
  imports = [
    ./java.nix
    ./nix.nix
    ./lua.nix
    ./python.nix
    ./typescript.nix
    ./rust.nix
    ./go.nix
    ./bash.nix
  ];
}
