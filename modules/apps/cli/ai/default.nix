# modules/apps/cli/ai/default.nix
# AI coding assistants with shared skills, context and MCP servers
{lib, ...}: {
  imports = [
    ./shared.nix # Skills and context every assistant receives
    ./project-environment.nix # Starts each agent in its project's direnv environment
    ./mcp # MCP server definitions
    ./claude-code.nix
    ./codex.nix
    ./claude-desktop.nix
    ./orca.nix
    ./t3code.nixos.nix
    ./ollama.nixos.nix
    (lib.mkRemovedOptionModule ["othrys" "apps" "ai" "opencode"] "othrys no longer supports OpenCode. Enable othrys.apps.ai.claude-code, which receives the same othrys.apps.ai.skills, othrys.apps.ai.context and MCP servers.")
  ];
}
