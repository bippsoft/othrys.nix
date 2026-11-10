# modules/apps/cli/default.nix
# CLI applications, no desktop environment required
{
  imports = [
    # Editor
    ./nixvim

    # Development
    ./development.nixos.nix
    ./gh.nix

    # Utilities
    ./comma.nix
    ./tmux.nix
    ./yazi.nix

    # AI Assistants
    ./ai
  ];
}
