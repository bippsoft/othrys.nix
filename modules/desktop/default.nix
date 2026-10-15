# modules/desktop/default.nix
# Desktop environment modules (theming, session management)
{
  config,
  lib,
  pkgs,
  ...
}: let
  session = import ./session.nix {inherit config pkgs;};
  compositorEnabled = config.othrys.desktop.compositors.hyprland.enable || config.othrys.desktop.compositors.niri.enable;

  locker = session.bySession "othrys-locker" {
    hyprland = "hyprlock";
    niri = "swaylock";
  };
in {
  imports = [
    ./ashell
    ./compositors
    ./idle.nix
    ./keyring.nix
    ./login.nix
    ./night-light.nix
    ./uwsm.nix
    ./wallpaper.nix
  ];

  options.othrys.desktop.defaultBrowser = lib.mkOption {
    type = lib.types.nonEmptyStr;
    default =
      if config.othrys.apps.floorp.enable
      then "floorp"
      else "firefox";
    defaultText = lib.literalMD ''
      `"floorp"` when `othrys.apps.floorp` is enabled, `"firefox"` otherwise
    '';
    example = "chromium";
    description = ''
      Browser command the browser shortcut of Hyprland and Niri runs, unless a
      compositor's own `browser` option is set. The default follows the
      browser module that is enabled. `firefox` is installed by no othrys
      module, so a host with another browser names it here. This selects a
      command only and sets no default application for links.
    '';
  };

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
  # needs to lock (ashell's lock button, the idle module's lock stage). The
  # default runs the locker of the running compositor.
  options.othrys.desktop.lockCommand = lib.mkOption {
    type = lib.types.str;
    default =
      if config.othrys.desktop.lockHooks == ""
      then locker
      else "${pkgs.writeShellScript "othrys-lock" ''
        ${config.othrys.desktop.lockHooks}
        exec ${locker}
      ''}";
    defaultText = lib.literalExpression ''"hyprlock" in a Hyprland session, "swaylock" otherwise'';
    description = "Command that locks the session; one authority for every lock consumer.";
  };

  # Shell lines the default lock command runs before the locker starts. A
  # module that keeps session data which should not outlive an unlocked
  # session adds its cleanup here, as ashell does for the clipboard history.
  # A host that sets lockCommand itself replaces the hooks with it.
  options.othrys.desktop.lockHooks = lib.mkOption {
    type = lib.types.lines;
    default = "";
    internal = true;
    description = "Shell lines the default lock command runs before the locker.";
  };

  # The file manager belongs to the graphical session and not to one
  # compositor, so it is installed here for either of them. It is a user-facing
  # application and goes into the user's packages.
  config = lib.mkIf compositorEnabled {
    othrys.internal.homeConfig."desktop.graphical" = {
      home.packages = [pkgs.nautilus];
    };
  };
}
