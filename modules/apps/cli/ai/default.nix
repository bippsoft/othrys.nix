# modules/apps/cli/ai/default.nix
# AI coding assistants with shared MCP servers
{
  imports = [
    ./mcp # MCP server definitions - must be first, other modules depend on it
    ./claude-code.nix
    ./ollama.nix
  ];
}
