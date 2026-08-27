# AI Assistants

AI assistant modules under `othrys.apps.ai.*`. Located in `modules/apps/cli/ai/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Claude Code | `othrys.apps.ai.claude-code` | Anthropic CLI assistant |
| Ollama | `othrys.apps.ai.ollama` | Local LLM inference server (CUDA/ROCm/Vulkan/CPU) |
| MCP GitHub | `othrys.apps.ai.mcp.github` | GitHub MCP server |
| MCP NixOS | `othrys.apps.ai.mcp.nixos` | NixOS MCP server |
| MCP Context7 | `othrys.apps.ai.mcp.context7` | Context7 documentation MCP server |

## MCP Servers

Model Context Protocol servers provide AI assistants with live tool access:

- **GitHub**: Repository operations, PR/issue management
- **NixOS**: Package search, option lookup, flake input queries
- **Context7**: Up-to-date library documentation and code examples

The GitHub server runs locally over stdio rather than against GitHub's hosted
endpoint, because `programs.mcp` accepts a file-backed environment variable
only for local servers. Home Manager turns that file reference into a wrapper
that reads the sops path at launch, so the personal access token lives in the
server process and nowhere else. It is no longer exported as `GITHUB_PAT` at
shell init, where every child of every interactive shell inherited it. Tooling
that relied on that variable needs its own source for the token.
