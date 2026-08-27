# modules/apps/gui/gaming/default.nix
# Gaming module aggregator for Steam, GameMode, MangoHud and the launchers
{
  imports = [
    ./steam.nix
    ./gamemode.nix
    ./mangohud.nix
    ./prismlauncher.nix
    ./osu.nix
    ./r2modman.nix
  ];
}
