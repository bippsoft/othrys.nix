# modules/apps/cli/ai/paseo.nix
# Paseo, a self-hosted daemon, CLI and desktop app for orchestrating coding agents
#
# The options, the packages, the refusals and the persisted paths, which hold
# on both platforms. paseo.nixos.nix and paseo.darwin.nix import this file and
# run the daemon as a systemd user unit or a launchd agent.
{
  config,
  lib,
  pkgs,
  othrysInputs,
  ...
}: let
  cfg = config.othrys.apps.ai.paseo;
  aiCfg = config.othrys.apps.ai;
  envCfg = aiCfg.projectEnvironment;
  llmAgents = import ./llm-agents.nix {inherit lib pkgs othrysInputs;};
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  jq = "${pkgs.jq}/bin/jq";

  # Paseo finds each agent on PATH and wraps none of them, so the daemon's
  # PATH starts with the host's own agents, through the project-environment
  # launcher, and nothing the host did not turn on. The direnv plugin runs
  # direnv and git from the same PATH.
  providers =
    lib.optional aiCfg.codex.enable config.othrys.internal.agents.codex
    ++ lib.optional aiCfg.claude-code.enable config.othrys.internal.agents.claude-code
    ++ lib.optionals cfg.direnv.enable [pkgs.direnv pkgs.git];

  # Where the daemon listens for each mode. The tailnet address and the
  # host's MagicDNS name are read when the daemon starts, and an empty answer
  # exits so the service tries again once tailscaled has an address. Paseo
  # refuses a Host header that is neither an address nor a listed name, so
  # both the full MagicDNS name and its first label are added to `hostnames`.
  listen = {
    loopback = ''
      export PASEO_LISTEN=127.0.0.1:${toString cfg.port}
    '';
    lan = ''
      export PASEO_LISTEN=0.0.0.0:${toString cfg.port}
    '';
    tailscale = ''
      tailscale=${config.services.tailscale.package}/bin/tailscale
      address=$("$tailscale" ip -4 2>/dev/null | ${pkgs.coreutils}/bin/head -n 1)
      if [ -z "$address" ]; then
        echo "paseo: tailscaled has no tailnet address yet" >&2
        exit 1
      fi
      export PASEO_LISTEN="$address:${toString cfg.port}"
      name=$("$tailscale" status --json 2>/dev/null | ${jq} -r '.Self.DNSName // empty')
      name=''${name%.}
      if [ -n "$name" ]; then
        hostnames="''${hostnames:+$hostnames,}$name,''${name%%.*}"
      fi
    '';
  };

  # Paseo enables a plugin only through config.json, which the daemon and
  # `paseo daemon set-password` also write. This script changes the
  # plugin's own entry and nothing else, and rewrites the file only when the
  # entry changes. With the plugin on it turns plugins on and points the
  # entry at the store path. With it off it removes an entry that points
  # into the store, which an earlier generation wrote, so a path the store
  # may have collected is never loaded. An entry the user pointed at a
  # checkout of their own stays. The temporary file has a name of its own,
  # since a switch and a start can run the script at once.
  # A config.json that jq cannot read, an empty one included, is left as it
  # is and the script fails. It runs as a process of its own, so the umask
  # that keeps config.json private reaches neither the daemon nor its agents.
  pluginConfig = pkgs.writeShellScript "paseo-plugin-config" (''
      set -u
      umask 077
      jq=${jq}
      home=''${PASEO_HOME:-$HOME/.paseo}
      config="$home/config.json"
      next=
      fail() {
        if [ -n "$next" ]; then
          ${pkgs.coreutils}/bin/rm -f "$next"
        fi
        echo "paseo: cannot update $config, which jq cannot read" >&2
        exit 1
      }
    ''
    + (
      if cfg.direnv.enable
      then ''
        ${pkgs.coreutils}/bin/mkdir -p "$home" || fail
        input=$config
        if [ ! -e "$config" ]; then
          input=${pkgs.writeText "paseo-config.json" "{}"}
        fi
        next=$(${pkgs.coreutils}/bin/mktemp "$config.XXXXXX") || fail
        "$jq" --arg path ${cfg.direnv.package} \
          '.pluginsEnabled = true | .plugins["paseo-direnv"] = {source: "directory", path: $path, enabled: true}' \
          "$input" > "$next" && [ -s "$next" ] || fail
      ''
      else ''
        [ -e "$config" ] || exit 0
        "$jq" -e --arg store ${builtins.storeDir}/ \
          '.plugins["paseo-direnv"]?.path? // "" | tostring | startswith($store)' "$config" > /dev/null
        case $? in
          0) ;;
          1) exit 0 ;;
          *) fail ;;
        esac
        next=$(${pkgs.coreutils}/bin/mktemp "$config.XXXXXX") || fail
        "$jq" 'del(.plugins["paseo-direnv"])' "$config" > "$next" && [ -s "$next" ] || fail
      ''
    )
    + ''
      if ${pkgs.diffutils}/bin/cmp -s "$next" "$config"; then
        ${pkgs.coreutils}/bin/rm -f "$next"
      else
        ${pkgs.coreutils}/bin/mv "$next" "$config" || fail
      fi
    '');

  # `paseo daemon start` runs the daemon in managed mode, which drops every
  # PASEO_* setting from the environment, so the service runs paseo-server
  # itself. The relay and web UI settings are always written, so config.json
  # cannot turn either on behind the module's back.
  serve = pkgs.writeShellScript "paseo-serve" (''
      set -eu
      export PASEO_HOME="$HOME/.paseo"
      export PASEO_RELAY_ENABLED=${lib.boolToString cfg.relay.enable}
      export PASEO_WEB_UI_ENABLED=${lib.boolToString cfg.webUi.enable}
      export PATH=${lib.makeBinPath providers}:$PATH
      ${pluginConfig}
    ''
    + lib.optionalString cfg.direnv.enable ''
      export PASEO_DIRENV_TRUST_WORKTREES=${
        if envCfg.trustWorktrees
        then "1"
        else "0"
      }
    ''
    + lib.optionalString (cfg.passwordFile != null) ''
      if [ ! -r ${lib.escapeShellArg cfg.passwordFile} ]; then
        echo "paseo: cannot read the password file "${lib.escapeShellArg cfg.passwordFile} >&2
        exit 1
      fi
      PASEO_PASSWORD=$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.passwordFile})
      export PASEO_PASSWORD
    ''
    + ''
      hostnames=${lib.escapeShellArg (lib.concatStringsSep "," cfg.hostnames)}
    ''
    + listen.${cfg.listen}
    + ''
      if [ -n "$hostnames" ]; then
        export PASEO_HOSTNAMES="$hostnames"
      fi
      exec ${cfg.package}/bin/paseo-server
    '');
in {
  options.othrys.apps.ai.paseo = {
    enable = lib.mkEnableOption "Paseo, a self-hosted daemon and CLI for orchestrating coding agents";

    package = lib.mkOption {
      type = lib.types.package;
      default = llmAgents.package "paseo";
      defaultText = lib.literalMD "the `paseo` package of the llm-agents flake this library locks";
      description = ''
        The Paseo package, which holds the `paseo` CLI and the `paseo-server`
        daemon. The default comes from cache.numtide.com, which the host then
        trusts.
      '';
    };

    service.enable = lib.mkEnableOption ''
      the Paseo daemon as a user service, a systemd unit on NixOS and a
      launchd agent on darwin. The desktop app attaches to this daemon
      instead of starting its own'';

    desktop = {
      enable = lib.mkEnableOption ''
        the Paseo desktop app, on Linux only. Without `service.enable` the app
        starts a daemon of its own, which reads none of the options below'';

      package = lib.mkOption {
        type = lib.types.package;
        default = llmAgents.package "paseo-desktop";
        defaultText = lib.literalMD "the `paseo-desktop` package of the llm-agents flake this library locks";
        description = ''
          The Paseo desktop package. The default comes from cache.numtide.com,
          which the host then trusts.
        '';
      };
    };

    listen = lib.mkOption {
      type = lib.types.enum ["loopback" "lan" "tailscale"];
      default = "loopback";
      description = ''
        Where the daemon listens. `"loopback"` keeps it to this host. `"lan"`
        binds every address and on NixOS opens `port` in the firewall.
        `"tailscale"` binds the host's tailnet address alone, admits the
        host's MagicDNS name in the Host header and on NixOS opens `port` on
        Tailscale's interface. Every peer that reaches the port can connect
        unless `passwordFile` is set.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6767;
      description = "Port the daemon listens on, which is upstream's own default.";
    };

    relay.enable = lib.mkEnableOption ''
      the hosted relay at relay.paseo.sh, through which a client outside the
      network reaches the daemon. The daemon then keeps an outbound
      connection to that server, and the traffic over it is end-to-end
      encrypted'';

    webUi.enable = lib.mkEnableOption ''
      the browser UI the daemon serves on its own port, beside its API and
      WebSocket. The page itself loads without the password, while the API
      behind it asks for one'';

    hostnames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["paseo.example.com"];
      description = ''
        Hostnames the daemon accepts in the Host header besides its own
        addresses, such as the name a reverse proxy serves it under. The
        daemon refuses any other name, which guards against DNS rebinding.
        `"tailscale"` adds the host's MagicDNS name on its own.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/paseo-password";
      description = ''
        A file holding the daemon's password, read when the daemon starts, so
        the password stays out of the store. It takes precedence over a hash
        that `paseo daemon set-password` wrote to `~/.paseo/config.json`.
      '';
    };

    direnv = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.service.enable && envCfg.enable;
        defaultText = lib.literalExpression "othrys.apps.ai.paseo.service.enable && othrys.apps.ai.projectEnvironment.enable";
        description = ''
          The paseo-direnv plugin in the daemon othrys runs. It loads the
          direnv environment of each agent's directory before the agent
          starts, and offers to allow a blocked `.envrc` in the app. A new
          git worktree inherits trust as
          othrys.apps.ai.projectEnvironment.trustWorktrees says, and the
          plugin's own toggle shows that value disabled.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = othrysInputs.paseo-direnv.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = lib.literalMD "the default package of the paseo-direnv flake this library locks";
        description = ''
          The paseo-direnv plugin, a directory holding its manifest and its
          TypeScript source, which Paseo compiles when it loads it.
        '';
      };
    };
  };

  options.othrys.internal.paseo = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    internal = true;
    readOnly = true;
    description = "The daemon's start script, for the platform files, and the script that edits config.json.";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.paseo = {inherit serve pluginConfig;};

    assertions = [
      {
        assertion = aiCfg.codex.enable || aiCfg.claude-code.enable;
        message = "othrys.apps.ai.paseo drives the host's own agents, and neither othrys.apps.ai.codex.enable nor othrys.apps.ai.claude-code.enable is set. Enable either one.";
      }
      {
        assertion = !cfg.desktop.enable || !isDarwin;
        message = "othrys.apps.ai.paseo.desktop.enable is set on darwin, and the llm-agents input builds the desktop app for Linux only. Unset it and use othrys.apps.ai.paseo.service.enable.";
      }
      {
        assertion = !cfg.desktop.enable || config.othrys.desktop.graphical;
        message = "othrys.apps.ai.paseo.desktop.enable requires a graphical session: enable othrys.desktop.compositors.hyprland or othrys.desktop.compositors.niri, or set othrys.desktop.graphical.";
      }
      {
        assertion = cfg.listen != "tailscale" || config.othrys.services.tailscale.enable;
        message = "othrys.apps.ai.paseo.listen = \"tailscale\" binds the host's tailnet address, which needs othrys.services.tailscale.enable.";
      }
      {
        assertion = cfg.service.enable || (cfg.listen == "loopback" && !cfg.relay.enable && !cfg.webUi.enable && cfg.hostnames == [] && cfg.passwordFile == null && !cfg.direnv.enable);
        message = "othrys.apps.ai.paseo.listen, relay.enable, webUi.enable, hostnames, passwordFile and direnv.enable configure the daemon othrys runs, and othrys.apps.ai.paseo.service.enable is unset. Set service.enable, or leave listen at \"loopback\", relay.enable, webUi.enable and direnv.enable off, hostnames empty and passwordFile null.";
      }
    ];

    warnings = lib.optional (cfg.service.enable && cfg.listen != "loopback" && cfg.passwordFile == null) "othrys.apps.ai.paseo.listen is \"${cfg.listen}\" and othrys.apps.ai.paseo.passwordFile is unset, so any peer that reaches port ${toString cfg.port} controls the host's agents unless `paseo daemon set-password` has stored a password in ~/.paseo/config.json.";

    othrys.internal.llmAgentsCache = true;

    # ~/.paseo holds config.json with the password hash, the daemon's key
    # pair, the plugins' settings, the agents' state and the git worktrees
    # with their uncommitted work. ~/.config/Paseo is the desktop app's
    # Electron profile, the name app.setName gives it on Linux.
    othrys.internal.persist."apps.ai.paseo" = {
      user.directories = map (directory: {
        inherit directory;
        mode = "0700";
      }) ([".paseo"] ++ lib.optional cfg.desktop.enable ".config/Paseo");
    };

    # A function, for Home Manager's own lib, which carries lib.hm.dag.
    othrys.internal.homeConfig."apps.ai.paseo" = {lib, ...}: {
      home.packages = [cfg.package] ++ lib.optional cfg.desktop.enable cfg.desktop.package;

      # With the plugin off, an entry an earlier generation wrote is removed
      # at the switch, so a daemon othrys does not start, such as the desktop
      # app's own, loads no collected store path either.
      home.activation.othrysPaseoDirenv = lib.mkIf (!cfg.direnv.enable) (lib.hm.dag.entryAfter ["writeBoundary"] ''
        run ${pluginConfig} || warnEcho "Paseo's config.json could not be read, so the paseo-direnv entry was not removed"
      '');
    };
  };
}
