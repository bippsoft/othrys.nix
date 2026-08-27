# modules/apps/gui/default.nix
# GUI applications, which require a desktop environment
{
  imports = [
    # Terminals
    ./kitty.nix
    ./ghostty.nix

    # Editors
    ./vscode
    ./idea.nix

    # Browsers
    ./floorp

    # Communication
    ./discord.nix
    ./vesktop.nix
    ./signal.nix

    # Media
    ./obs.nix
    ./picard.nix
    ./plexamp.nix
    ./mpv.nix

    # Utilities
    ./localsend.nix
    ./rustdesk.nix

    # Gaming
    ./gaming
  ];
}
