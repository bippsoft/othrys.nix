# AI Assistants

AI assistant modules under `othrys.apps.ai.*`. Located in `modules/apps/cli/ai/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Claude Code | `othrys.apps.ai.claude-code` | Anthropic CLI assistant |
| Codex | `othrys.apps.ai.codex` | OpenAI CLI assistant |
| Ollama | `othrys.apps.ai.ollama` | Local LLM inference server, with the backend chosen from the host's GPU |
| MCP Context7 | `othrys.apps.ai.mcp.context7` | Context7 documentation MCP server |

## Where the AI packages come from

The packages of `othrys.apps.ai.claude-code` and `othrys.apps.ai.codex`
default to the builds in the
[llm-agents](https://github.com/numtide/llm-agents.nix) flake this library
locks. That flake follows each vendor's releases within hours, while nixpkgs
typically trails by days. It builds against its own nixpkgs, so its packages
come prebuilt from `cache.numtide.com`, and a host trusts that cache and its
key only while such a module is on. `package` takes any other build, such as
`pkgs.claude-code`.

The default is built with `disableTelemetry`, which turns off telemetry and
non-essential traffic, and `othrys.apps.ai.claude-code.disableTelemetry =
false` builds it without. A package set by hand is used as given.

llm-agents marks its unfree packages as free, so nixpkgs never asks whether
the host admits them. Claude Code is unfree, so the module refuses a host
that admits no unfree software, through `othrys.system.nix.allowUnfree` or
the host's own `allowUnfreePredicate` or `allowUnfreePackages`.

## Codex

`othrys.apps.ai.codex` wraps Home Manager's `programs.codex`. It receives the
shared skills, the shared context as its global `AGENTS.md`, and every server
under `programs.mcp.servers`. `othrys.apps.ai.codex.skills` holds skills for
Codex alone.

`disableTelemetry`, on by default, turns off Codex's analytics and the
metrics exporter that follows them, `/feedback` uploads, and the startup
check that asks GitHub for a newer release a Nix-managed binary cannot
install. `othrys.apps.ai.codex.settings` is merged over what the module
writes and wins over it.

The sign-in goes to the desktop keyring where one answers and to
`~/.codex/auth.json` otherwise. `config.toml` is merged at each activation
rather than linked read-only, since Codex records trusted directories there
itself. Under impermanence the module persists `~/.codex` at mode `0700`,
which holds the sign-in file, the sessions, the history and the state
database.

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

## Ollama

`othrys.apps.ai.ollama` runs the Ollama server on `127.0.0.1:11434`, pulls the
models in `loadModels` at start, and persists them. `acceleration` picks the
package, and its default follows the host. An `othrys.hardware.nvidia` host
gets `ollama-cuda`, any other host with `hardware.graphics.enable` gets
`ollama-vulkan`, which runs on AMD and Intel cards, and a host without graphics
gets `ollama-cpu`. An AMD host that wants ROCm sets `acceleration = "rocm"`.
The CUDA build is unfree and pulls the CUDA toolkit, so a host without an
NVIDIA card never gets it by default.

## MCP Servers

Model Context Protocol servers provide AI assistants with live tool access.
`othrys.apps.ai.mcp.context7` serves up-to-date library documentation and code
examples, and takes no credential.

The NixOS MCP server is gone. It depended on `fastmcp`, which nixpkgs marked
broken, and the nix CLI answers the same questions. `nix search nixpkgs` finds
packages, and `man configuration.nix` and `man home-configuration.nix` list the
options. A host that still sets `othrys.apps.ai.mcp.nixos` fails evaluation
with that advice.

## GitHub

There is no GitHub MCP server. An agent reaches GitHub through the `gh` CLI,
which acts with the user's own login, so no separate long-lived token is kept
for the agent. [`othrys.apps.gh`](./apps.md#github-cli) configures it, and on a
host that also enables Claude Code it adds the read-only `gh` commands to the
allow-list. Reading an issue, a pull request, a workflow run or a release then
runs without a prompt, while every command that writes to GitHub is prompted.

`othrys.apps.ai.mcp.github` is a removed option, and a host that still sets it
fails at evaluation with a message naming `othrys.apps.gh`.
