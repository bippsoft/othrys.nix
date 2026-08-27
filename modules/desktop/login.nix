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
  cfg = config.othrys.desktop.login;
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
      type = lib.types.str;
      description = ''
        Wayland session the default `sessionCommand` launches via `uwsm start`
        (e.g. hyprland-uwsm.desktop). Unused when `sessionCommand` is set
        explicitly (e.g. niri hosts) and ignored by cosmic-greeter, which
        lists the installed sessions instead.
      '';
    };

    sessionCommand = lib.mkOption {
      type = lib.types.str;
      default = "uwsm start ${cfg.defaultDesktop}";
      defaultText = lib.literalExpression ''"uwsm start ''${defaultDesktop}"'';
      description = ''
        Command the greeter runs to start the session. The default launches
        `defaultDesktop` through uwsm (the hyprland path); compositors that
        manage their own session set this directly, e.g. "niri-session".
      '';
    };

    autoLogin = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip the greeter and launch defaultDesktop directly (tuigreet only). Security tradeoff, so enable deliberately.";
    };
  };
  # ANCHOR_END: login-options

  # ANCHOR: login-config
  config = lib.mkIf cfg.enable {
    # tuigreet is the minimal greeter that launches the default session.
    services.greetd = lib.mkIf (cfg.greeter == "tuigreet") {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd '${cfg.sessionCommand}'";
          user = username;
        };

        initial_session = lib.mkIf cfg.autoLogin {
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
