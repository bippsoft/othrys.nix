# modules/desktop/vicinae.nix
# Vicinae launcher, run as a user server and opened from the launcher chord
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.desktop.vicinae;
  theme = config.othrys.theme;
  themed = theme.palette != null;
  # Read only where `themed` holds. Null without a palette.
  colors = theme.colors.withHashtag;
  font = theme.fonts.sansSerif;

  # cliphist keeps the history the bar and its chord show, and wipes it at
  # lock and at logout. Vicinae's own history would hold the same entries
  # past both, so it stops recording while cliphist runs.
  cliphistRuns = config.othrys.desktop.ashell.enable && config.othrys.desktop.ashell.clipboard.enable;

  vicinae = lib.getExe cfg.package;
  # A chord that opens one command directly. `toggle` closes the window
  # when the chord is pressed while it is open.
  deeplink = command: [vicinae "vicinae://launch/${command}?toggle=true"];

  # The theme file Home Manager writes to ~/.local/share/vicinae/themes. Every
  # key left out is derived by Vicinae from the core colours or taken from
  # the built-in theme named by `inherits`.
  othrysTheme = {
    meta = {
      version = 1;
      name = "othrys";
      description = "The othrys.theme palette";
      variant = theme.polarity;
      inherits = "vicinae-${theme.polarity}";
    };
    colors = {
      core = {
        background = colors.base00;
        foreground = colors.base05;
        secondary_background = colors.base01;
        border = colors.base02;
        accent = colors.base0D;
        accent_foreground = colors.base00;
      };
      accents = {
        red = colors.base08;
        orange = colors.base09;
        yellow = colors.base0A;
        green = colors.base0B;
        cyan = colors.base0C;
        blue = colors.base0D;
        purple = colors.base0E;
        magenta = colors.base0E;
      };
    };
  };

  # Curated defaults are written here rather than as the option's default,
  # since an option default is discarded wholesale by any definition and a
  # host setting one key would lose the rest. Per-leaf mkDefault hands the
  # layering to the module system, as the GameMode module does.
  curated = lib.mkMerge [
    {
      # nixpkgs patches the shipped default to false. It is written here as
      # well so that a `package` from another build keeps telemetry off.
      telemetry.system_info = lib.mkDefault false;
      # Vicinae otherwise asks a third-party service for the icon of every
      # link it shows, which hands that service the host name of each one.
      favicon_service = lib.mkDefault "none";
      # The launcher opens at the root search, not at the view it was
      # closed on.
      pop_to_root_on_close = lib.mkDefault true;
      input_server.enabled = lib.mkDefault cfg.inputServer.enable;
    }
    (lib.mkIf cliphistRuns {
      providers.clipboard.preferences.monitoring = lib.mkDefault false;
    })
    (lib.mkIf themed {
      theme = {
        dark.name = lib.mkDefault "othrys";
        light.name = lib.mkDefault "othrys";
      };
    })
    (lib.mkIf (font != null) {
      font.normal.family = lib.mkDefault font.name;
    })
  ];
in {
  # ANCHOR: vicinae-options
  options.othrys.desktop.vicinae = {
    enable = lib.mkEnableOption "the Vicinae launcher";

    package = lib.mkPackageOption pkgs "vicinae" {};

    settings = lib.mkOption {
      # The type of programs.vicinae.settings in Home Manager, which renders
      # it as JSON.
      inherit (pkgs.formats.json {}) type;
      default = {};
      example = lib.literalExpression ''
        {
          favicon_service = "twenty";
          search_files_in_root = true;
          launcher_window.layer_shell.keyboard_interactivity = "on_demand";
        }
      '';
      description = ''
        Vicinae settings, merged over the curated defaults. Those are
        written at mkDefault, so a key set here replaces that key alone and
        its siblings stay. The shape is that of
        `~/.config/vicinae/settings.json`, and `vicinae config default`
        prints every key with its upstream value.

        The curated defaults turn telemetry off, set `favicon_service` to
        `"none"`, set `pop_to_root_on_close` to true and set
        `input_server.enabled` from `inputServer.enable`. With a palette in
        `othrys.theme` both theme names are `"othrys"`, and with
        `othrys.theme.fonts.sansSerif` set the interface font is that font.
        While ashell keeps its cliphist history,
        `providers.clipboard.preferences.monitoring` is false, so Vicinae
        records no second history that the wipe at lock would miss. On a
        host without that history Vicinae records the clipboard itself.

        The declared settings are merged over the file Vicinae writes from
        its settings window, key by key, each time the server loads them. A
        change made in the window to a key declared here has no effect.
      '';
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression ''
        [
          (config.lib.vicinae.mkRayCastExtension {
            name = "gif-search";
            rev = "4d417c2dfd86a5b2bea202d4a7b48d8eb3dbaeb1";
            sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          })
        ]
      '';
      description = ''
        Extensions to install, passed to Home Manager's
        `programs.vicinae.extensions`. Home Manager's `config.lib.vicinae`
        builds them, and that attribute exists only inside the user's Home
        Manager configuration.
      '';
    };

    launcher = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Make `vicinae toggle` the desktop launcher by setting
        `othrys.desktop.launcherCommand`. The chord that runs it, `Mod+D` on
        Niri and `$mainMod + D` on Hyprland, and the launcher button of the
        bar both belong to `othrys.desktop.ashell`, so a host without the bar
        binds the command itself. With false the launcher stays wofi. The
        emoji, clipboard menu, file search and run signals beside it follow
        Vicinae either way, and a host sets any of them to keep its own.
      '';
    };

    inputServer.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run Vicinae's input helper, which pastes into the focused window and
        expands snippets. The helper reads every keyboard of the host and
        injects keys through uinput, so it is installed as a security
        wrapper with `cap_dac_override`, which any local account can run,
        and the `uinput` kernel module is loaded. With false Vicinae copies
        to the clipboard where it would paste, and snippets do not expand.
      '';
    };
  };
  # ANCHOR_END: vicinae-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.othrys.desktop.graphical;
        message = "othrys.desktop.vicinae requires a graphical session: enable othrys.desktop.compositors.hyprland or othrys.desktop.compositors.niri, or set othrys.desktop.graphical.";
      }
    ];

    # A default rather than a plain definition, so a host that sets the
    # launcher command itself wins without lib.mkForce.
    othrys.desktop.launcherCommand = lib.mkIf cfg.launcher (lib.mkDefault [vicinae "toggle"]);

    # The pickers follow the launcher's pattern. Each opens one Vicinae
    # command, and pressing the chord again closes it. The emoji search
    # copies the emoji unless the input server is on, since pasting goes
    # through it. Vicinae has no prompt that runs a typed command, so the
    # run chord is left unbound and the root search starts programs.
    othrys.desktop.emojiCommand = lib.mkDefault (deeplink "core/search-emojis");
    othrys.desktop.dmenuCommand = lib.mkDefault [vicinae "dmenu"];
    othrys.desktop.fileSearchCommand = lib.mkDefault (deeplink "files/search");
    othrys.desktop.runCommand = lib.mkDefault null;

    # The same wrapper Vicinae's own NixOS module installs. The server finds
    # it through VICINAE_INPUT_SERVER_BIN, set on the unit below.
    security.wrappers = lib.mkIf cfg.inputServer.enable {
      vicinae-input-server = {
        source = "${cfg.package}/libexec/vicinae/vicinae-input-server";
        capabilities = "cap_dac_override+ep";
        owner = "root";
        group = "root";
      };
    };
    boot.kernelModules = lib.mkIf cfg.inputServer.enable ["uinput"];

    othrys.internal.persist."desktop.vicinae" = {
      user.directories = [
        # settings.json, which the settings window writes.
        ".config/vicinae"
        # The clipboard history, snippets, shortcuts and extension data.
        {
          directory = ".local/share/vicinae";
          mode = "0700";
        }
        # onboarding.json, without which the onboarding screen returns after
        # every boot, beside the log. The file index under ~/.cache is
        # rebuilt by Vicinae and is left to the wipe.
        {
          directory = ".local/state/vicinae";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."desktop.vicinae" = {
      programs.vicinae = {
        enable = true;
        inherit (cfg) package extensions;
        # The declared settings go to home-manager.json, which the server
        # reads through VICINAE_OVERRIDES, and settings.json stays a file
        # Vicinae can write. Without it settings.json is a link into the
        # store, and every change made in the settings window is lost.
        mutableSettings = true;
        systemd.enable = true;
        settings = lib.mkMerge [curated cfg.settings];
        themes = lib.mkIf themed {othrys = othrysTheme;};
      };

      # No sandbox baseline. The server is a GPU client of the user's own
      # session and starts the user's programs, which would inherit every
      # restriction placed on the unit.
      systemd.user.services.vicinae = {
        Unit.ConditionEnvironment = "WAYLAND_DISPLAY";
        Service = {
          # Home Manager writes `always`, which restarts the server five
          # seconds after "Quit Vicinae" in the tray menu has stopped it.
          Restart = lib.mkForce "on-failure";
          Slice = "session.slice";
          Environment = lib.mkIf cfg.inputServer.enable [
            "VICINAE_INPUT_SERVER_BIN=${config.security.wrapperDir}/vicinae-input-server"
          ];
        };
      };
    };
  };
}
