# modules/system/shell/zsh.darwin.nix
# The nix-darwin implementation of othrys.system.shell.zsh
{
  config,
  lib,
  pkgs,
  ...
}: let
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.system.shell.zsh;
in {
  imports = [./zsh.nix];

  # The persisted paths of zsh.nixos.nix have no counterpart, since a Mac
  # keeps its root filesystem across boots.
  config = lib.mkIf cfg.enable {
    programs.zsh.enable = true;

    # Enabling the shell makes it the primary user's login shell. On
    # nix-darwin the option reaches the account only when
    # othrys.system.users.uid hands the account to nix-darwin.
    othrys.system.users.defaultShell = lib.mkIf usersEnabled (lib.mkDefault pkgs.zsh);

    # The clipboard preset maps pbcopy and pbpaste onto wl-copy and
    # wl-paste. macOS ships pbcopy and pbpaste itself and has no Wayland
    # session, so the preset is off although a Mac is a graphical host.
    othrys.system.shell.zsh.aliasPresets.clipboard = lib.mkDefault false;
  };
}
