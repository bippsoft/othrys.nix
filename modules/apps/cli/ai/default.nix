# modules/apps/cli/ai/default.nix
# AI coding assistants with shared skills, context and MCP servers
{lib, ...}: {
  imports = [
    ./shared.nix # Skills and context every assistant receives
    ./mcp # MCP server definitions
    ./claude-code.nix
    ./codex.nix
    ./claude-desktop.nix
    ./ollama.nix
    (lib.mkRemovedOptionModule ["othrys" "apps" "ai" "opencode"] "othrys no longer supports OpenCode. Enable othrys.apps.ai.claude-code, which receives the same othrys.apps.ai.skills, othrys.apps.ai.context and MCP servers.")
  ];
}
