# modules/apps/cli/ai/default.nix
# AI coding assistants with shared skills, context and MCP servers
{
  imports = [
    ./shared.nix # Skills and context every assistant receives
    ./mcp # MCP server definitions
    ./claude-code.nix
    ./ollama.nix
  ];
}
