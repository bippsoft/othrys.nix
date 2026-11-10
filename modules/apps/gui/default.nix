# modules/apps/gui/default.nix
# GUI applications, which require a desktop environment
{
  imports = [
    # Terminals
    ./kitty.nix
    ./ghostty.nixos.nix

    # Editors
    ./vscode
    ./idea.nix

    # Browsers
    ./floorp
    ./chromium.nix

    # Communication
    ./discord.nixos.nix
    ./vesktop.nixos.nix
    ./signal.nix

    # Media
    ./obs.nix
    ./picard.nix
    ./plexamp.nix
    ./mpv.nix

    # Utilities
    ./localsend.nix
    ./remmina.nix
    ./rustdesk.nix

    # Gaming
    ./gaming
  ];
}
