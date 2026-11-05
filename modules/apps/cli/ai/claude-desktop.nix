# modules/apps/cli/ai/claude-desktop.nix
# Claude Desktop with the local MCP servers merged into its config at activation
{
  config,
  lib,
  pkgs,
  othrysInputs,
  ...
}: let
  cfg = config.othrys.apps.ai.claude-desktop;
  llmAgents = import ./llm-agents.nix {inherit lib pkgs othrysInputs;};
in {
  options.othrys.apps.ai.claude-desktop = {
    enable = lib.mkEnableOption "Claude Desktop";

    package = lib.mkOption {
      type = lib.types.package;
      default = llmAgents.package "claude-desktop";
      defaultText = lib.literalMD "the `claude-desktop` package of the llm-agents flake this library locks";
      description = ''
        The Claude Desktop package. The default repackages Anthropic's own
        Linux build and comes from cache.numtide.com, which the host then
        trusts.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.othrys.desktop.graphical;
        message = "othrys.apps.ai.claude-desktop requires a graphical session: enable othrys.desktop.compositors.hyprland or othrys.desktop.compositors.niri, or set othrys.desktop.graphical.";
      }
      {
        assertion = llmAgents.unfreeAllowed "claude-desktop";
        message = llmAgents.unfreeMessage "othrys.apps.ai.claude-desktop" "claude-desktop";
      }
    ];

    othrys.internal.llmAgentsCache = true;

    # ~/.config/Claude is the app's Electron profile, its logs and its config
    # file. The sign-in is in the desktop keyring. The layout inside is not
    # documented, so the directory is persisted whole, at 0700.
    othrys.internal.persist."apps.ai.claude-desktop" = {
      user.directories = [
        {
          directory = ".config/Claude";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.ai.claude-desktop" = {
      home.packages = [cfg.package];

      imports = [
        # Home Manager's own lib, which carries lib.hm.dag.
        ({
          config,
          lib,
          ...
        }: let
          # Claude Desktop reads local servers, the ones with a command, from
          # its config file. Remote servers are added in the app itself.
          # Home Manager's server type gives every server a command, null on
          # a remote one.
          local = lib.filterAttrs (_: server: (server.command or null) != null) config.programs.mcp.servers;
          servers = lib.mapAttrs (_: server:
            lib.filterAttrs (name: value: builtins.elem name ["command" "args" "env"] && value != null && value != [] && value != {}) server)
          local;
          jq = lib.getExe pkgs.jq;
        in {
          # The app writes its preferences into the same file and has been
          # seen to rewrite the whole of it, so the file stays writable and
          # each activation sets mcpServers alone. With no local server
          # declared, the file is left as the app keeps it.
          home.activation.othrysClaudeDesktopMcp = lib.mkIf (servers != {}) (lib.hm.dag.entryAfter ["writeBoundary"] ''
            file="$HOME/.config/Claude/claude_desktop_config.json"
            run mkdir -p "$(dirname "$file")"
            current='{}'
            readable=1
            if [ -e "$file" ]; then
              if ! current=$(cat "$file" 2> /dev/null); then
                readable=
                warnEcho "Claude Desktop's config could not be read, so its MCP servers were not written: $file"
              elif [ -z "''${current//[[:space:]]/}" ]; then
                current='{}'
              fi
            fi
            if [ -n "$readable" ]; then
              if merged=$(printf '%s' "$current" | ${jq} --argjson servers ${lib.escapeShellArg (builtins.toJSON servers)} '.mcpServers = $servers'); then
                run install -m 0600 /dev/stdin "$file" <<< "$merged"
              else
                warnEcho "Claude Desktop's config is not valid JSON, so its MCP servers were not written: $file"
              fi
            fi
          '');
        })
      ];
    };
  };
}
