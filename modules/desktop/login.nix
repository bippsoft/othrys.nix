# modules/desktop/login.nix
# Graphical login manager. greetd is the common backend, and the `greeter` option
# selects the frontend (tuigreet TUI or System76's cosmic-greeter).
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.desktop.login;
  niriEnabled = config.othrys.desktop.compositors.niri.enable;
  lockPath = config.othrys.desktop.idle.enable || config.othrys.desktop.noctalia.enable;

  # The session the greeter starts when the host does not say. A compositor
  # that registers a uwsm entry sets defaultDesktop; niri runs its own session
  # manager. A host with neither names the command itself, and the assertion
  # below says so instead of a module-system error about defaultDesktop.
  defaultSession =
    if cfg.defaultDesktop != null
    then "uwsm start ${cfg.defaultDesktop}"
    else if niriEnabled
    then "niri-session"
    else "";
in {
  # ANCHOR: login-options
  options.othrys.desktop.login = {
    enable = lib.mkEnableOption "graphical login manager (greetd)";

    greeter = lib.mkOption {
      type = lib.types.enum ["tuigreet" "cosmic-greeter"];
      default = "tuigreet";
      description = "Greeter frontend. Both run on greetd.";
    };

    defaultDesktop = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Wayland session the default `sessionCommand` launches via `uwsm start`
        (e.g. hyprland-uwsm.desktop). The hyprland module sets it. Unused when
        `sessionCommand` is set explicitly and ignored by cosmic-greeter, which
        lists the installed sessions instead.
      '';
    };

    sessionCommand = lib.mkOption {
      type = lib.types.str;
      default = defaultSession;
      defaultText = lib.literalExpression ''"uwsm start ''${defaultDesktop}" when a compositor sets defaultDesktop, "niri-session" on a niri host, otherwise required'';
      description = ''
        Command the greeter runs to start the session. The default launches
        `defaultDesktop` through uwsm when a compositor registered one, which
        hyprland does, and `niri-session` on a niri host. A host running a
        desktop othrys does not manage sets it directly.
      '';
    };

    autoLogin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Skip the greeter and start the session as the primary user (tuigreet
        only). Anyone at the console gets the session, so the host must lock
        it on idle and before sleep, which `othrys.desktop.idle` or noctalia
        provides, and the module refuses the option without one of them.
      '';
    };
  };
  # ANCHOR_END: login-options

  # ANCHOR: login-config
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sessionCommand != "";
        message = "othrys.desktop.login has no session to start: enable a compositor module, or set othrys.desktop.login.sessionCommand for a desktop othrys does not manage.";
      }
      {
        assertion = cfg.autoLogin -> lockPath;
        message = "othrys.desktop.login.autoLogin starts a session for whoever is at the console, so the host needs a lock path: enable othrys.desktop.idle or othrys.desktop.noctalia.";
      }
      {
        assertion = cfg.autoLogin -> usersEnabled;
        message = "othrys.desktop.login.autoLogin starts the session as the primary user, which needs othrys.system.users.enable.";
      }
    ];

    # tuigreet is the minimal greeter that launches the default session. The
    # greeter itself runs as the `greeter` account nixpkgs creates, since it
    # draws the prompt before anyone has authenticated; only the session
    # started after login runs as the primary user. useTextGreeter keeps
    # kernel messages off the terminal the TUI draws on.
    services.greetd = lib.mkIf (cfg.greeter == "tuigreet") {
      enable = true;
      useTextGreeter = true;
      settings = {
        default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd '${cfg.sessionCommand}'";

        initial_session = lib.mkIf (cfg.autoLogin && usersEnabled) {
          command = cfg.sessionCommand;
          user = username;
        };
      };
    };

    # cosmic-greeter is System76's graphical greeter, which configures greetd itself.
    services.displayManager.cosmic-greeter.enable = cfg.greeter == "cosmic-greeter";
  };
  # ANCHOR_END: login-config
}
