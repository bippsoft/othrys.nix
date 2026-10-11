# modules/apps/cli/ai/mcp/default.nix
# Base MCP configuration, enabling upstream programs.mcp
#
# Individual server configs are defined in their own modules. They register
# themselves under home-manager's programs.mcp.servers.<name>.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.ai.mcp;

  # Check if any MCP server sub-module is enabled
  anyMcpEnabled = cfg.nixos.enable || cfg.context7.enable;
in {
  imports = [
    ./nixos.nix
    ./context7.nix
    (lib.mkRemovedOptionModule ["othrys" "apps" "ai" "mcp" "github"] "The GitHub MCP server kept a personal access token in the host's secrets. The gh CLI does the same work with the user's own login, so enable othrys.apps.gh and run `gh auth login`. With Claude Code on, othrys.apps.gh pre-approves the read-only gh commands.")
  ];

  config = lib.mkIf anyMcpEnabled {
    othrys.internal.homeConfig."apps.ai.mcp".programs.mcp.enable = true;
  };
}
