# modules/desktop/session.nix
# Picks a command by the compositor the session runs under
#
# Not a NixOS module, just a plain function the desktop modules import, as
# hyprland-lua.nix is.
#
# A host can enable both compositors and let the greeter choose, so which
# module is enabled says nothing about which compositor is running. Every
# command that talks to a compositor (screen power, logout, the locker) is
# built here, which keeps the test for the running session in one place.
{
  config,
  pkgs,
}: let
  hyprland = config.othrys.desktop.compositors.hyprland.enable;
  niri = config.othrys.desktop.compositors.niri.enable;
in {
  # Which lockers a host needs installed, each with its PAM service. A host
  # with both compositors needs both, since each session runs its own.
  hyprlock = hyprland;
  swaylock = niri || !hyprland;

  # `commands` holds one shell command per compositor. A host with a single
  # compositor gets that command as a plain string. A host with both gets a
  # script that reads XDG_CURRENT_DESKTOP, which each compositor sets for its
  # session and exports to the systemd user manager, so the test also holds
  # inside user units such as hypridle.
  bySession = name: commands:
    if hyprland && niri
    then "${pkgs.writeShellScript name ''
      case "''${XDG_CURRENT_DESKTOP:-}" in
        *[Nn]iri*) exec ${commands.niri} ;;
        *) exec ${commands.hyprland} ;;
      esac
    ''}"
    else if hyprland
    then commands.hyprland
    else commands.niri;
}
