# modules/apps/cli/nixvim/plugins/default.nix
# Plugin module aggregator
_: {
  imports = [
    ./lsp-base.nix
    ./completion.nix
    ./snippets.nix
    ./treesitter.nix
    ./picker.nix
    ./git.nix
    ./statusline.nix
    ./which-key.nix
    ./notifications.nix
    ./dashboard.nix
    ./navigation.nix
    ./editor.nix
    ./formatting.nix
    ./diagnostics.nix
    ./utilities.nix
  ];
}
