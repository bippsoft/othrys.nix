# modules/theme/stylix.darwin.nix
# The nix-darwin implementation of othrys.system.stylix
#
# Exported as darwinModules.stylix and left out of darwinModules.default, so
# a host imports it together with the Stylix darwin module or imports
# neither. Stylix on darwin themes the fonts, jankyborders and neovim at the
# system level and declares no cursor or console target. Everything else it
# themes is in the user's Home Manager configuration, so a host imports
# darwinModules.home as well. stylix.nix turns the user's GTK target off on
# darwin. stylix.nix holds every write, and this
# file adds none.
{
  imports = [./stylix.nix];
}
