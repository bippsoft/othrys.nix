# modules/apps/cli/nixvim/globals.nix
# Leader keys, set before any plugin binds a mapping
_: {
  programs.nixvim.globals = {
    mapleader = " ";
    maplocalleader = " ";
  };
}
