# modules/apps/cli/nixvim/extraPackages.nix
# Tools nixvim plugins shell out to, installed alongside the editor
{pkgs, ...}: {
  programs.nixvim.extraPackages = with pkgs; [
    # General tools (used across multiple languages/plugins)
    ripgrep # Required by snacks.picker grep, todo-comments
    fd # File finding

    lazygit # Git TUI
    glow # Markdown preview
  ];
}
