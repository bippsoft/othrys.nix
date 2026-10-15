# AI Assistants

AI assistant modules under `othrys.apps.ai.*`. Located in `modules/apps/cli/ai/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Claude Code | `othrys.apps.ai.claude-code` | Anthropic CLI assistant |
| OpenCode | `othrys.apps.ai.opencode` | Open source terminal assistant for any provider |
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

## Shared skills and context

Two things are declared once and handed to every enabled assistant.

`othrys.apps.ai.skills` holds skills in the Agent Skills layout, keyed by
name. A value is the text of a `SKILL.md`, the path of one, or the path of a
directory that holds one. A name is lower-case letters, digits and single
hyphens, and any other name is refused at evaluation. A skill for one tool
alone goes to that tool's own option, such as
`othrys.apps.ai.claude-code.skills`, and an entry there replaces a shared one
of the same name.

```nix
othrys.apps.ai.skills.release-notes = ./skills/release-notes;
```

`othrys.apps.ai.context` is the global context. Its first part describes the
host the assistant runs on, and `context.nixos.enable = false` leaves it out.
The line about the root wipe is rendered from
`othrys.system.impermanence.enable`, so a host with a persistent root is not
told its root is wiped. The line about where to store data follows the same
option. It says "only in `$HOME`" on a host that wipes its root and suggests
the home directory on every other host. `context.extra` holds the host's own
lines, which follow that text. `context.text` is the rendered result.

`othrys.apps.ai.mcp.context` is a removed option, and its text is
`othrys.apps.ai.context.text`.

## OpenCode

`othrys.apps.ai.opencode` wraps Home Manager's `programs.opencode`. It
receives the shared skills, the shared context as its global `AGENTS.md`, and
every server under `programs.mcp.servers`.

OpenCode's own defaults allow every edit and every command without a prompt.
The module writes a permission map that prompts for both, lets the read-only
git commands through and denies `rm -rf` and `sudo`. As with Claude Code, the
map saves prompts and catches a careless mistake, and it is not a security
boundary. `permissions.edit` and `permissions.extraBash` change it. The last
matching pattern wins and the patterns are written in alphabetical order, so
the catch-all `*` comes first and a named command overrides it.

```nix
othrys.apps.ai.opencode = {
  enable = true;
  permissions.extraBash."cargo test*" = "allow";
  settings.model = "ollama/llama3.1";
};
```

`othrys.apps.ai.opencode.share` defaults to `"disabled"`, which blocks
session sharing. Sharing uploads the session's conversation history to
OpenCode's servers and creates a public URL accessible to anyone with the
link. `"manual"` allows `/share` without sharing automatically, while
`"auto"` publishes every new conversation automatically. The
[upstream sharing documentation](https://opencode.ai/docs/share/) describes
these modes and what becomes public.

`othrys.apps.ai.opencode.settings.share` overrides the typed `share` option.
The module writes a global default to `~/.config/opencode/opencode.json`,
and project configuration and runtime configuration can override it under
OpenCode's [configuration precedence](https://opencode.ai/docs/config/#precedence-order).
This setting is not a security boundary or an upload policy. Do not rely on
the generated global default to prevent uploads from a project or session.

`settings` is merged over what the module writes to `opencode.json` and wins,
and `tui` becomes `tui.json`. `skills`, `agents` and `commands` are for
OpenCode alone, since the frontmatter of an agent or a command differs between
the two tools.

On a host that enables `othrys.apps.ai.ollama`, the module adds a provider for
the local server with the models in `ollama.loadModels`.
`opencode.ollama.enable = false` leaves it out.

OpenCode also reads Claude Code's files. With both tools enabled, the shared
skills reach it through `~/.claude/skills` and are written once, and the
skills declared for Claude Code alone are visible to it as well.
`claudeCompat = false` turns that off, and the shared skills are then written
to OpenCode's own directory.

Provider credentials are entered with `opencode auth login` and stay in
`~/.local/share/opencode`, which is persisted at mode 0700 on a host with an
ephemeral root. The module pre-approves no MCP tool for OpenCode.

### Options

The [generated option reference](../reference/options.md) lists the
`othrys.apps.ai.opencode` options, their types and defaults.

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
