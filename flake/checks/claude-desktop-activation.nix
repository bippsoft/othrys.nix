# flake/checks/claude-desktop-activation.nix
# CORE. The claude-desktop activation step, run against the files a user's
# app may have left. The step only exists as shell that Home Manager runs on
# the host, so evaluating it proves nothing about what it writes. It is taken
# from an evaluated host and run here with Home Manager's run and warnEcho
# stubbed, and each result is read back with jq.
{
  pkgs,
  hostConfig,
  functioningHost,
}: let
  host = hostConfig [
    functioningHost
    {
      othrys.desktop.graphical = true;
      othrys.system.nix.allowUnfree = true;
      othrys.apps.ai.claude-desktop.enable = true;
      othrys.internal.homeConfig."fixture.mcp" = {
        programs.mcp.servers.local-fixture = {
          command = "fixture-server";
          args = ["--stdio"];
        };
      };
    }
  ];
  step = pkgs.writeText "claude-desktop-mcp-step" host.home-manager.users.${host.othrys.system.user.name}.home.activation.othrysClaudeDesktopMcp.data;
in
  pkgs.runCommand "othrys-claude-desktop-activation" {nativeBuildInputs = [pkgs.jq pkgs.coreutils];} ''
    set -euo pipefail
    run() { "$@"; }
    warnEcho() { echo "warning: $*" >&2; }
    fresh() {
      HOME=$(mktemp -d)
      export HOME
      file="$HOME/.config/Claude/claude_desktop_config.json"
    }
    seed() {
      mkdir -p "$(dirname "$file")"
      printf '%s' "$1" > "$file"
    }

    fresh
    seed '{"preferences":{"sidebarMode":"chat"}}'
    source ${step}
    jq -e '.preferences.sidebarMode == "chat" and .mcpServers["local-fixture"].command == "fixture-server"' "$file"
    [ "$(stat -c %a "$file")" = 600 ]
    echo "the app's own keys survive beside the servers"

    fresh
    source ${step}
    jq -e '.mcpServers["local-fixture"].args == ["--stdio"]' "$file"
    echo "a missing file is created with the servers"

    fresh
    seed 'not json{'
    source ${step} 2> warning
    [ "$(cat "$file")" = 'not json{' ]
    grep -q "not valid JSON" warning
    echo "invalid JSON is left as it is, with a warning"

    fresh
    seed '   '
    source ${step}
    jq -e '.mcpServers | has("local-fixture")' "$file"
    echo "a file of whitespace counts as empty"

    fresh
    seed '{"preferences":{}}'
    chmod 000 "$file"
    source ${step} 2> warning
    chmod 600 "$file"
    [ "$(cat "$file")" = '{"preferences":{}}' ]
    grep -q "could not be read" warning
    echo "an unreadable file is left as it is, with a warning, and activation goes on"

    touch $out
  ''
