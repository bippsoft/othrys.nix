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
    ./vicinae.nix
    ./wallpaper.nix
  ];

  # ANCHOR: desktop-options
  options.othrys.desktop.defaultBrowser = lib.mkOption {
    type = lib.types.nonEmptyStr;
    default =
      if config.othrys.apps.floorp.enable
      then "floorp"
      else if config.othrys.apps.chromium.enable
      then "chromium"
      else "firefox";
    defaultText = lib.literalMD ''
      `"floorp"` when `othrys.apps.floorp` is enabled, `"chromium"` when
      `othrys.apps.chromium` is, and `"firefox"` otherwise
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
  # ANCHOR_END: desktop-options

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

  # The single "open the launcher" command, consumed by ashell's launcher
  # chord and its launcher button. A module that provides a launcher sets it
  # at mkDefault, as the Vicinae module does, so the host keeps the last word.
  options.othrys.desktop.launcherCommand = lib.mkOption {
    type = lib.types.nonEmptyListOf lib.types.str;
    default = ["wofi" "--show" "drun"];
    defaultText = lib.literalMD ''
      `["<vicinae>/bin/vicinae" "toggle"]` when `othrys.desktop.vicinae` is
      enabled with `launcher` on, and `["wofi" "--show" "drun"]` otherwise
    '';
    example = ["fuzzel"];
    description = ''
      The launcher as a program and its arguments. Niri spawns the list as
      it is, and Hyprland and the bar's launcher button run it through the
      shell with each element quoted.
    '';
  };

  # The pickers beside the launcher, consumed by ashell's chords and its
  # clipboard button in the same way. The defaults are the tools ashell
  # installs, and ashell installs each of them only while a command here
  # still names it. A module that provides a picker sets these at mkDefault,
  # as the Vicinae module does.
  options.othrys.desktop.emojiCommand = lib.mkOption {
    type = lib.types.nullOr (lib.types.nonEmptyListOf lib.types.str);
    default = ["rofimoji" "--selector" "wofi" "--clipboarder" "wl-copy" "--typer" "wtype" "--action" "type"];
    defaultText = lib.literalMD ''
      Vicinae's emoji search when `othrys.desktop.vicinae` is enabled, and
      rofimoji through wofi, typing with wtype, otherwise
    '';
    example = ["rofimoji" "--action" "copy"];
    description = ''
      The emoji picker as a program and its arguments, run by ashell's
      `Mod+E` chord on Niri and Hyprland. With null the chord is not bound.
    '';
  };

  options.othrys.desktop.dmenuCommand = lib.mkOption {
    type = lib.types.nonEmptyListOf lib.types.str;
    default = ["wofi" "--dmenu"];
    defaultText = lib.literalMD ''
      `vicinae dmenu` when `othrys.desktop.vicinae` is enabled, and
      `["wofi" "--dmenu"]` otherwise
    '';
    example = ["fuzzel" "--dmenu"];
    description = ''
      A menu that reads choices on standard input and prints the chosen
      line. ashell's clipboard button and its `Mod+Shift+V` chord pipe the
      cliphist history through it.
    '';
  };

  options.othrys.desktop.runCommand = lib.mkOption {
    type = lib.types.nullOr (lib.types.nonEmptyListOf lib.types.str);
    default = ["wofi" "--show" "run"];
    defaultText = lib.literalMD ''
      null when `othrys.desktop.vicinae` is enabled, and
      `["wofi" "--show" "run"]` otherwise
    '';
    description = ''
      A prompt that runs a command typed into it, bound by ashell to
      `Mod+Shift+D`. With null the chord is not bound.
    '';
  };

  options.othrys.desktop.fileSearchCommand = lib.mkOption {
    type = lib.types.nullOr (lib.types.nonEmptyListOf lib.types.str);
    default = null;
    defaultText = lib.literalMD ''
      Vicinae's file search when `othrys.desktop.vicinae` is enabled, and
      null otherwise
    '';
    description = ''
      A file search, bound by ashell to `Mod+Shift+F`. With null the chord
      is not bound.
    '';
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

  config = lib.mkMerge [
    # The file manager belongs to the graphical session and not to one
    # compositor, so it is installed here for either of them. It is a
    # user-facing application and goes into the user's packages.
    (lib.mkIf compositorEnabled {
      othrys.internal.homeConfig."desktop.graphical" = {
        home.packages = [pkgs.nautilus];
      };
    })

    # The locker sits beside the lock command that names it, so it is there
    # whichever module locks the session. That is every compositor host, and
    # a host with an unmanaged compositor whose idle module locks it. The
    # locker is a PAM client, and a PAM service that is not declared denies
    # every attempt, so a lock screen with no service cannot be unlocked.
    # programs.hyprlock declares hyprlock's and installs the package. swaylock
    # has no NixOS module, and niri-flake declares its service only on niri
    # hosts, so it is declared here for every host that locks with it. A host
    # with both compositors gets both lockers. The YubiKey module adds its
    # factor to both services itself.
    (lib.mkIf (compositorEnabled || config.othrys.desktop.idle.enable) {
      programs.hyprlock.enable = session.hyprlock;
      security.pam.services = lib.mkIf session.swaylock {swaylock = {};};
      environment.systemPackages = lib.optional session.swaylock pkgs.swaylock;
    })
  ];
}
