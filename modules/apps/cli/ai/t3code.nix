# modules/apps/cli/ai/t3code.nix
# T3 Code, a web and desktop control surface for coding agents
#
# The options, the packages, the refusals and the persisted paths, which hold
# on both platforms. t3code.nixos.nix and t3code.darwin.nix import this file
# and run the headless server as a systemd user unit or a launchd agent.
{
  config,
  lib,
  pkgs,
  othrysInputs,
  ...
}: let
  cfg = config.othrys.apps.ai.t3code;
  aiCfg = config.othrys.apps.ai;
  llmAgents = import ./llm-agents.nix {inherit lib pkgs othrysInputs;};
  inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;

  # The agents T3 Code drives are the host's own, so it runs the builds those
  # modules configured and nothing the host did not turn on.
  providers =
    lib.optional aiCfg.codex.enable aiCfg.codex.package
    ++ lib.optional aiCfg.claude-code.enable aiCfg.claude-code.package;

  # Wraps one program of one output. A build that finds no program fails, so
  # a renamed binary cannot drop the flags unnoticed.
  wrap = {
    base,
    program,
    flags,
    postBuild ? "",
  }:
    pkgs.symlinkJoin {
      name = "${program}-${base.version or "wrapped"}";
      paths = [base];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild =
        ''
          if [ ! -e "$out/bin/${program}" ]; then
            echo "othrys.apps.ai.t3code: no ${program} program in ${base}" >&2
            exit 1
          fi
          wrapProgram "$out/bin/${program}" ${lib.escapeShellArgs flags}
        ''
        + postBuild;
      passthru.unwrapped = base;
      meta = (base.meta or {}) // {mainProgram = program;};
    };

  telemetry = lib.optionals cfg.disableTelemetry ["--set-default" "T3CODE_TELEMETRY_ENABLED" "false"];

  cli = wrap {
    base = cfg.package;
    program = "t3";
    flags = telemetry;
  };

  # The bundle name upstream exports, which a package set by hand may lack.
  appName = cfg.package.unwrapped.appName or "T3 Code (Beta)";
  desktop = wrap {
    base = cfg.package.desktop;
    program = "t3code-desktop";
    # A self-updating app inside the store either fails to replace itself or
    # drifts from the version the flake locks. The launcher path is the one
    # the app writes into its t3code:// handler on Linux, which would
    # otherwise name the inner wrapper and start the app without these flags.
    flags =
      telemetry
      ++ ["--set" "T3CODE_DISABLE_AUTO_UPDATE" "1"]
      ++ lib.optionals isLinux ["--set" "T3CODE_DESKTOP_LAUNCHER_PATH" "${placeholder "out"}/bin/t3code-desktop"];
    # The bundle's executable is a relative link that reaches this wrapper
    # only while the bundle sits four levels below bin. It is pointed at the
    # wrapper by its full path instead, and a bundle that is not where the
    # name says fails the build, so the app started from Finder cannot skip
    # these flags unnoticed.
    postBuild = lib.optionalString isDarwin ''
      macos="$out/Applications/${appName}.app/Contents/MacOS"
      if [ ! -L "$macos/${appName}" ]; then
        echo "othrys.apps.ai.t3code: no ${appName}.app bundle in ${cfg.package.desktop}" >&2
        exit 1
      fi
      rm "$macos/${appName}"
      ln -s "$out/bin/t3code-desktop" "$macos/${appName}"
    '';
  };

  # The headless server's command line for each listen mode. `--lan` binds
  # every address and drops any peer that is not loopback, LAN or tailnet,
  # and only while no host is given. The tailnet address is read when the
  # server starts, and an empty answer exits so the service tries again once
  # tailscaled has one.
  commands = {
    loopback = ''
      exec ${cli}/bin/t3 serve --host 127.0.0.1 --port ${toString cfg.port}
    '';
    lan = ''
      exec ${cli}/bin/t3 serve --lan --port ${toString cfg.port}
    '';
    tailscale = ''
      address=$(${config.services.tailscale.package}/bin/tailscale ip -4 2>/dev/null | ${pkgs.coreutils}/bin/head -n 1)
      if [ -z "$address" ]; then
        echo "t3code: tailscaled has no tailnet address yet" >&2
        exit 1
      fi
      exec ${cli}/bin/t3 serve --host "$address" --port ${toString cfg.port}
    '';
  };
  serve = pkgs.writeShellScript "t3code-serve" commands.${cfg.listen};
in {
  options.othrys.apps.ai.t3code = {
    enable = lib.mkEnableOption "T3 Code, a control surface for coding agents";

    package = lib.mkOption {
      type = lib.types.package;
      default = (llmAgents.package "t3code").override {providerPackages = providers;};
      defaultText = lib.literalMD ''
        the `t3code` package of the llm-agents flake this library locks, with
        the packages of `othrys.apps.ai.codex` and `othrys.apps.ai.claude-code`
        as its agents, each one while its module is on
      '';
      description = ''
        The T3 Code package, whose `out` output holds the `t3` server and
        whose `desktop` output holds the desktop app. The default comes from
        cache.numtide.com, which the host then trusts. Upstream's own default
        puts five agents ahead of the user's PATH, three of them unfree. A
        package set here is used as given.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["headless" "desktop"]);
      default = null;
      description = ''
        `"headless"` installs `t3` and runs `t3 serve` as a user service, a
        systemd unit on NixOS and a launchd agent on darwin. `"desktop"`
        installs the desktop app, which starts its own server while a window
        is open, beside `t3`. The two cannot share one `~/.t3`, since the
        second server finds the first one's lock and exits, so a host picks
        one.
      '';
    };

    listen = lib.mkOption {
      type = lib.types.enum ["loopback" "lan" "tailscale"];
      default = "loopback";
      description = ''
        Where the headless server listens. `"loopback"` keeps it to this
        host. `"lan"` binds every address and drops any peer outside
        loopback, the private ranges and the tailnet, and on NixOS opens
        `port` in the firewall. `"tailscale"` binds the host's tailnet
        address alone and on NixOS opens `port` on Tailscale's interface.
        Every mode but loopback asks a new client to pair, with a link from
        `t3 pair`.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Port the headless server listens on, which is upstream's own default.";
    };

    disableTelemetry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start `t3` and the desktop app with `T3CODE_TELEMETRY_ENABLED` set
        to false, which turns off the product events T3 Code sends.
      '';
    };
  };

  options.othrys.internal.t3code = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    internal = true;
    readOnly = true;
    description = "The wrapped `t3` and desktop packages and the headless server command, for the platform files.";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.t3code = {inherit cli desktop serve;};

    assertions = [
      {
        assertion = cfg.mode != null;
        message = "othrys.apps.ai.t3code.mode is unset. Set it to \"headless\" to run the server as a user service, or to \"desktop\" for the desktop app.";
      }
      {
        assertion = aiCfg.codex.enable || aiCfg.claude-code.enable;
        message = "othrys.apps.ai.t3code drives the host's own agents, and neither othrys.apps.ai.codex.enable nor othrys.apps.ai.claude-code.enable is set. Enable either one.";
      }
      {
        assertion = cfg.mode != "desktop" || config.othrys.desktop.graphical;
        message = "othrys.apps.ai.t3code.mode = \"desktop\" requires a graphical session: enable othrys.desktop.compositors.hyprland or othrys.desktop.compositors.niri, or set othrys.desktop.graphical.";
      }
      {
        assertion = cfg.mode != "desktop" || cfg.listen == "loopback";
        message = "othrys.apps.ai.t3code.listen is \"${cfg.listen}\", which sets where the headless server listens, while othrys.apps.ai.t3code.mode is \"desktop\". Set mode to \"headless\" or listen to \"loopback\".";
      }
      {
        assertion = cfg.listen != "tailscale" || config.othrys.services.tailscale.enable;
        message = "othrys.apps.ai.t3code.listen = \"tailscale\" binds the host's tailnet address, which needs othrys.services.tailscale.enable.";
      }
    ];

    othrys.internal.llmAgentsCache = true;

    # ~/.t3 holds the database with the threads and pairing sessions, the
    # server's secrets, the settings and the git worktrees with the agents'
    # uncommitted work, and the desktop app keeps its own settings there too.
    # ~/.config/t3code-v2 is the desktop app's Electron profile, the name
    # DesktopUserData.ts sets on Linux. ~/.cache/t3code is a compile cache and
    # stays on the ephemeral root.
    othrys.internal.persist."apps.ai.t3code" = {
      user.directories = map (directory: {
        inherit directory;
        mode = "0700";
      }) ([".t3"] ++ lib.optional (cfg.mode == "desktop") ".config/t3code-v2");
    };

    othrys.internal.homeConfig."apps.ai.t3code" = {
      home.packages = [cli] ++ lib.optional (cfg.mode == "desktop") desktop;
    };
  };
}
