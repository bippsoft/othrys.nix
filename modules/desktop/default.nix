# modules/desktop/default.nix
# Desktop environment modules (theming, session management)
{
  config,
  lib,
  ...
}: {
  imports = [
    ./ashell
    ./compositors
    ./idle.nix
    ./login.nix
    ./night-light.nix
    ./noctalia.nix
    ./uwsm.nix
  ];

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

  # The single "lock this session" command, consumed by every module that
  # needs to lock (ashell's lock button, the idle module's lock stage).
  # Compositor-flavored default. Shell layers with their own lock (noctalia)
  # override it.
  options.othrys.desktop.lockCommand = lib.mkOption {
    type = lib.types.str;
    default =
      if config.othrys.desktop.compositors.hyprland.enable
      then "hyprlock"
      else "swaylock";
    defaultText = lib.literalExpression ''"hyprlock" on hyprland hosts, "swaylock" otherwise (noctalia sets "noctalia msg session lock")'';
    description = "Command that locks the session; one authority for every lock consumer.";
  };
}
