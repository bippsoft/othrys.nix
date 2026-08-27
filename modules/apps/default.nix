# modules/apps/default.nix
# Application module aggregator (cli and gui)
{
  imports = [
    ./cli
    ./gui
    ./languages
  ];
}
