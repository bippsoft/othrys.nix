# modules/apps/cli/ai/orca.nix
# Orca, a desktop app that runs coding agents side by side in git worktrees
{
  config,
  lib,
  pkgs,
  othrysInputs,
  ...
}: let
  cfg = config.othrys.apps.ai.orca;
  llmAgents = import ./llm-agents.nix {inherit lib pkgs othrysInputs;};

  # Orca sends usage telemetry to PostHog from a new install unless this
  # variable is set. --set-default leaves a value the session sets alone.
  quiet = base:
    pkgs.symlinkJoin {
      name = "orca-${base.version or "unwrapped"}";
      paths = [base];
      nativeBuildInputs = [pkgs.makeWrapper];
      # A build that finds no program to wrap fails, so a renamed binary
      # cannot turn telemetry back on unnoticed. A desktop entry that names
      # the unwrapped package by path is rewritten to start the wrapper.
      postBuild = ''
        wrapped=
        for program in orca-ide orca; do
          if [ -e "$out/bin/$program" ]; then
            wrapProgram "$out/bin/$program" --set-default ORCA_TELEMETRY_DISABLED 1
            wrapped=1
          fi
        done
        if [ -z "$wrapped" ]; then
          echo "othrys.apps.ai.orca: no orca-ide or orca program in ${base}, so telemetry could not be turned off" >&2
          exit 1
        fi
        for entry in "$out"/share/applications/*.desktop; do
          [ -L "$entry" ] || continue
          target=$(readlink -f "$entry")
          rm "$entry"
          substitute "$target" "$entry" --replace-quiet "${base}" "$out"
        done
      '';
      passthru.unwrapped = base;
      inherit (base) meta;
    };
  package =
    if cfg.disableTelemetry
    then quiet cfg.package
    else cfg.package;
in {
  options.othrys.apps.ai.orca = {
    enable = lib.mkEnableOption "Orca, a desktop app for running coding agents side by side";

    package = lib.mkOption {
      type = lib.types.package;
      default = llmAgents.package "orca";
      defaultText = lib.literalMD "the `orca` package of the llm-agents flake this library locks";
      description = ''
        The Orca package. The default repackages upstream's own Linux build
        and comes from cache.numtide.com, which the host then trusts.
      '';
    };

    disableTelemetry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Wrap the package so that Orca starts with `ORCA_TELEMETRY_DISABLED`
        set, which turns its usage telemetry off.
      '';
    };

    tailscale = {
      enable = lib.mkEnableOption ''
        reaching Orca's runtime port over the tailnet, for pairing another
        device. The port opens on Tailscale's interface and on no other, and
        Orca's network pairing must also be turned on in the app'';

      port = lib.mkOption {
        type = lib.types.port;
        default = 6768;
        description = "Orca's runtime port, which is Orca's own default.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.othrys.desktop.graphical;
        message = "othrys.apps.ai.orca requires a graphical session: enable othrys.desktop.compositors.hyprland or othrys.desktop.compositors.niri, or set othrys.desktop.graphical.";
      }
      {
        assertion = !cfg.tailscale.enable || config.othrys.services.tailscale.enable;
        message = "othrys.apps.ai.orca.tailscale.enable opens Orca's port on the tailnet, which needs othrys.services.tailscale.enable.";
      }
    ];

    othrys.internal.llmAgentsCache = true;

    # ~/.config/Orca holds the profiles, the database, the logs and the agent
    # permission setting, ~/.orca the API key files, and ~/orca/workspaces the
    # git worktrees with the agents' uncommitted work.
    othrys.internal.persist."apps.ai.orca" = {
      user.directories =
        map (directory: {
          inherit directory;
          mode = "0700";
        }) [
          ".config/Orca"
          ".orca"
          "orca/workspaces"
        ];
    };

    othrys.internal.homeConfig."apps.ai.orca" = {
      home.packages = [package];
    };

    networking.firewall.interfaces = lib.mkIf cfg.tailscale.enable {
      ${config.services.tailscale.interfaceName}.allowedTCPPorts = [cfg.tailscale.port];
    };
  };
}
