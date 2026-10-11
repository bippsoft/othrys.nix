# AI Assistants

AI assistant modules under `othrys.apps.ai.*`. Located in `modules/apps/cli/ai/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Claude Code | `othrys.apps.ai.claude-code` | Anthropic CLI assistant |
| Ollama | `othrys.apps.ai.ollama` | Local LLM inference server (CUDA/ROCm/Vulkan/CPU) |
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

Three defaults follow from that. Every allow-list entry names a tool and a
command prefix, and no bare tool name appears, since a bare `Edit` approves
every edit and is `acceptEdits` by another route. `Bash(just:*)`,
`Bash(find:*)`, `Bash(nix eval:*)` and `Bash(nix fmt:*)` are absent, because
each one runs whatever a repository hands it, through a recipe, `-exec`,
`--expr` or the repository's own formatter. And `permissions.defaultMode` is
`"default"`, so edits are prompted rather than applied. Hosts that want any
of them back set `permissions.extraAllow` and `permissions.defaultMode`
explicitly, which keeps the decision visible in the host configuration rather
than inherited from a library. The module registers no hooks of its own.

`theme` takes one of Claude Code's six themes, `dark`, `light`,
`dark-daltonized`, `light-daltonized`, `dark-ansi` and `light-ansi`. Any other
value is refused at evaluation.

The shared context every MCP-enabled assistant receives describes the host it
runs on. Its line about the root wipe is rendered from
`othrys.system.impermanence.enable`, so a host with a persistent root is not
told its root is wiped. The line about where to store data follows the same
option. It says "only in `$HOME`" on a host that wipes its root and suggests
the home directory on every other host.

## MCP Servers

Model Context Protocol servers provide AI assistants with live tool access:

- **NixOS**: Package search, option lookup, flake input queries
- **Context7**: Up-to-date library documentation and code examples

Neither server takes a credential.

## GitHub

There is no GitHub MCP server. An agent reaches GitHub through the `gh` CLI,
which acts with the user's own login, so no separate long-lived token is kept
for the agent. [`othrys.apps.gh`](./apps.md#github-cli) configures it, and on a
host that also enables Claude Code it adds the read-only `gh` commands to the
allow-list. Reading an issue, a pull request, a workflow run or a release then
runs without a prompt, while every command that writes to GitHub is prompted.

`othrys.apps.ai.mcp.github` is a removed option, and a host that still sets it
fails at evaluation with a message naming `othrys.apps.gh`.
