# modules/apps/cli/default.nix
# CLI applications, no desktop environment required
{
  imports = [
    # Editor
    ./nixvim

    # Development
    ./development.nix
    ./gh.nix

    # Utilities
    ./comma.nix
    ./yazi.nix

    # AI Assistants
    ./ai
  ];
}
