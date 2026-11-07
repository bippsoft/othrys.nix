# modules/desktop/graphical.nix
# The othrys.desktop.graphical option, shared by the NixOS and nix-darwin trees
{lib, ...}: {
  # The single "this host runs a graphical session" signal. Every othrys
  # compositor module sets it when enabled, and modules outside desktop/ key
  # their GUI-flavored behavior (tray applets, GUI pinentry, clipboard tools,
  # theming surface) on THIS flag, never on a specific compositor's enable,
  # so adding a compositor never requires touching them. Hosts running a
  # compositor othrys doesn't manage set it explicitly.
  options.othrys.desktop.graphical = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Whether this host runs a graphical session. Set automatically by
      othrys compositor modules (e.g. compositors.hyprland); set it manually
      when the host runs a desktop othrys doesn't manage.
    '';
  };
}
