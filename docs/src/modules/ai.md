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

## What the Claude Code permission lists are for

`othrys.apps.ai.claude-code` ships an allow-list and a deny-list, and it is
worth being plain about what they do. They reduce prompting for commands you
would approve anyway, and they catch a careless mistake. They are not a
security boundary.

A rule matches a command string, and a string has endless spellings. `rm -rf`
is denied while `rm -fr` is not. `sudo` is denied while `pkexec` is not.
`Read(./.env)` is denied while `cat .env` arrives as a Bash invocation and
matches nothing. Anything that can run a shell can reach whatever the user can
reach, so the boundary that actually holds is whether the repository is one you
trust.

Two defaults follow from that. `Bash(just:*)` is not on the allow-list, because
a justfile recipe is arbitrary shell and allowing it hands any repository
unreviewed execution. And `permissions.defaultMode` is `"default"`, so edits
are prompted rather than applied. Hosts that want either back set
`permissions.extraAllow` and `permissions.defaultMode` explicitly, which keeps
the decision visible in the host configuration rather than inherited from a
library.

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
