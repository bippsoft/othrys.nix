# AI Assistants

**Platforms:** Claude Code, Codex, T3 Code in both its modes, Ollama, the shared context and the MCP servers run on NixOS and nix-darwin, and Claude Desktop and Orca are NixOS only. See [Darwin](../architecture/darwin.md).

AI assistant modules under `othrys.apps.ai.*`. Located in `modules/apps/cli/ai/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Claude Code | `othrys.apps.ai.claude-code` | Anthropic CLI assistant |
| Codex | `othrys.apps.ai.codex` | OpenAI CLI assistant |
| Claude Desktop | `othrys.apps.ai.claude-desktop` | Anthropic's desktop app, which also runs Claude Code sessions |
| Orca | `othrys.apps.ai.orca` | Desktop app that runs coding agents side by side in git worktrees |
| T3 Code | `othrys.apps.ai.t3code` | Web and desktop interface to Codex and Claude Code, served headless or run as a desktop app |
| Ollama | `othrys.apps.ai.ollama` | Local LLM inference server, with the backend chosen from the host's GPU |
| MCP Context7 | `othrys.apps.ai.mcp.context7` | Context7 documentation MCP server |

## Where the AI packages come from

The packages of `othrys.apps.ai.claude-code`, `othrys.apps.ai.codex`,
`othrys.apps.ai.claude-desktop`, `othrys.apps.ai.orca` and
`othrys.apps.ai.t3code` default to the builds in the
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
the host admits them. Claude Code and Claude Desktop are unfree, so their
modules refuse a host that admits no unfree software, through
`othrys.system.nix.allowUnfree` or the host's own `allowUnfreePredicate` or
`allowUnfreePackages`.

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

### How Codex's permissions follow Claude Code's

Codex confines commands with a sandbox where Claude Code prompts for them,
so the module carries Claude Code's choices over in Codex's own terms.

- **Mode.** `permissions.mode` takes Claude Code's two mode names. With
  `"default"` the workspace stays read-only and every edit asks first. With
  `"acceptEdits"` Codex edits the workspace without asking and also runs
  commands without asking, inside a sandbox with no network that writes only
  to the workspace. Codex has no mode that applies edits freely while
  prompting for every command. In both modes, leaving the sandbox asks first.
- **Read denials.** `permissions.denyRead` keeps sandboxed commands from
  reading `.env`, `.env.*` and `secrets/**`, as Claude Code's deny list does.
  Codex expresses that only through its permission profiles, which it marks
  as Beta, so the module writes a profile named `othrys` that extends the
  built-in one the mode names. A command run outside the sandbox is not bound
  by it.
- **Command rules.** `sudo` and `rm -rf` are `forbidden` in `othrys.rules`,
  which blocks them under every mode. `permissions.extraRules` appends lines
  in Codex's rule syntax. An `allow` rule runs its command outside the
  sandbox, so the only allow rules the modules write are the read-only `gh`
  commands, which need the network the sandbox withholds. Codex appends the
  commands a user chooses to always allow to `default.rules`, which the
  modules leave alone.
- **Commit attribution.** Codex adds a `Co-authored-by: Codex` trailer when
  the ChatGPT account's commit attribution setting is on. That setting lives
  on OpenAI's servers, and no `config.toml` key turns it off, so turn it off
  in the account's Codex settings. An instruction in `AGENTS.md` does not
  override it.

The sign-in goes to the desktop keyring where one answers and to
`~/.codex/auth.json` otherwise. `config.toml` is merged at each activation
rather than linked read-only, since Codex records trusted directories there
itself. Under impermanence the module persists `~/.codex` at mode `0700`,
which holds the sign-in file, the sessions, the history and the state
database.

## Claude Desktop

`othrys.apps.ai.claude-desktop` installs Anthropic's desktop app for the user,
repackaged from Anthropic's own Linux build. It needs a graphical session and
refuses a host without one. Cowork's virtual machines need `qemu` and KVM from
the host, which the module does not provide.

The app reads local MCP servers, the ones with a command, from
`~/.config/Claude/claude_desktop_config.json`. It keeps its preferences in
the same file, so the file stays writable, and each activation sets its
`mcpServers` key to the local servers under `programs.mcp.servers`. Remote
servers such as Context7 are added in the app's own settings. With no local
server declared, the file is left as the app keeps it, so removing the last
local server leaves the entries the previous activation wrote, to be removed
in the app or by hand. The app reads the file
at launch, so a running app picks up a change after a restart.

Under impermanence the module persists `~/.config/Claude` at mode `0700`,
which holds the app's profile, its logs and the config file. The sign-in sits
in the desktop keyring.

## Orca

By default, Orca starts Claude Code with `--dangerously-skip-permissions` and
Codex with `--dangerously-bypass-approvals-and-sandbox`. Every permission
prompt is then gone for the sessions it starts, Claude Code's deny list no
longer applies, and Codex runs outside its sandbox. The setting lives in
Orca's own state, which no module can declare, so turn it off once per user
in **Settings → Agents → Agent Permissions → Manual**. The choice persists
with the rest of Orca's state.

`othrys.apps.ai.orca` installs Orca for the user and needs a graphical
session. Each task runs in its own git worktree under `~/orca/workspaces`.
Orca finds Claude Code, Codex and the other agents on the login shell's
`PATH` and bundles none of them. It writes status hooks into Claude Code's
and Codex's settings, which is why both keep their settings writable.

`disableTelemetry`, on by default, wraps the package so that Orca starts with
`ORCA_TELEMETRY_DISABLED` set, since a new install otherwise reports usage to
PostHog. Orca still shows a notice when a newer release exists and downloads
nothing.

Orca's runtime port, 6768 by default, binds to loopback until network pairing
is turned on in the app. The module opens it on no interface by default.
`othrys.apps.ai.orca.tailscale.enable` opens it on Tailscale's interface
alone, and refuses a host without othrys Tailscale. A client then passes the
tailnet's ACLs and Orca's per-client pairing token, and the tailnet's ACL
policy should limit that port to the user's own devices. The port is never
opened on the LAN, and Orca's own documentation advises against exposing it.

Under impermanence the module persists `~/.config/orca`, `~/.orca` and
`~/orca/workspaces`, each at mode `0700`. They hold the profiles and the
permission setting above, the API key files, and the worktrees with the
agents' uncommitted work.

## T3 Code

`othrys.apps.ai.t3code` installs T3 Code, a web and desktop interface that
runs coding agents in threads. It installs `t3` for the user in both modes.
The agents it drives are the host's own Codex and Claude Code packages, each
one while its module is on, and the module refuses a host with neither.
Upstream's default package instead bundles five agents ahead of the user's
`PATH`, three of them unfree.

`mode` has no default, and a host that leaves it unset is refused. With
`"headless"` the module runs `t3 serve` as a systemd user unit on NixOS and
as a launchd agent on nix-darwin, restarted whenever it exits. On a NixOS
host where othrys manages the user with Home Manager, the user lingers, so
the unit runs from boot with nobody logged in. A launchd agent runs only
while the user is logged in, so a Mac that serves T3 Code logs the user in
at boot. With `"desktop"` it installs the desktop app, which starts its own
server while a window is open, and it refuses a host without a graphical
session. Only one server can use `~/.t3`. A second one finds the first one's
lock in `~/.t3/userdata/server-owner.sqlite` and exits, and the desktop app
then quits with "This T3 home is unavailable". A workstation in desktop mode
reaches a headless host by adding it in the app as a saved environment.

```nix
# A headless host on the tailnet
othrys.services.tailscale.enable = true;
othrys.apps.ai.codex.enable = true;
othrys.apps.ai.t3code = {
  enable = true;
  mode = "headless";
  listen = "tailscale";
};

# A workstation
othrys.apps.ai.claude-code.enable = true;
othrys.apps.ai.t3code = {
  enable = true;
  mode = "desktop";
};
```

`listen` applies to the headless server alone, and desktop mode refuses any
value but `"loopback"`. `"lan"` passes upstream's `--lan`, which binds every
address and drops a peer outside loopback, the private ranges and the
tailnet. On NixOS it opens `port` in the firewall. othrys controls no
firewall on macOS, so there the peer filter and pairing are what protect the
port. `"tailscale"` binds the tailnet IPv4 address that `tailscale ip -4`
gives when the server starts. With no address the server exits, and the
service starts it again ten seconds later until tailscaled has one. On NixOS
it opens `port` on Tailscale's interface alone, and it refuses a host without
`othrys.services.tailscale.enable`.
Traffic is plain HTTP inside WireGuard. Upstream's `--tailscale-serve` is not
used, since its HTTPS needs node certificates from the control server, which
headscale 0.29 does not issue.

Every mode but loopback asks a new client to pair. The server writes a
pairing link at start, valid for five minutes, to the journal on NixOS and to
`~/Library/Logs/t3code.log` on darwin. `t3 pair` mints a new one later.

```console
$ journalctl --user -u t3code
$ t3 pair
```

`disableTelemetry`, on by default, starts `t3` and the desktop app with
`T3CODE_TELEMETRY_ENABLED=false`. The desktop app also always starts with
`T3CODE_DISABLE_AUTO_UPDATE=1`, since an app in the store cannot replace
itself.

Under impermanence the module persists `~/.t3` at mode `0700`, which holds
the threads database, the server's secrets, the settings and the git
worktrees with the agents' uncommitted work. Desktop mode also persists the
Electron profile in `~/.config/t3code-v2` at `0700`. `~/.cache/t3code` is a
compile cache and is not persisted. The agents' sign-ins live in `~/.codex`
and `~/.claude`, which their own modules persist.

### Options

```nix
{{#include ../../../modules/apps/cli/ai/t3code.nix:t3code-options}}
```

## Claude Code's settings file

Claude Code's `settings.json` is merged at each activation rather than linked
read-only. The declared settings win, while keys that Claude Code or a program
it runs adds itself stay in place, such as the status hooks Orca writes. A
host that wants the file read-only sets
`home-manager.users.<name>.programs.claude-code.mutableSettings = false`.

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
It defaults to off on darwin, where the text about NixOS does not apply.
The line about the root wipe is rendered from
`othrys.system.impermanence.enable`, so a host with a persistent root is not
told its root is wiped. The line about where to store data follows the same
option. It says "only in `$HOME`" on a host that wipes its root and suggests
the home directory on every other host. `context.extra` holds the host's own
lines, which follow that text. `context.text` is the rendered result.

`othrys.apps.ai.mcp.context` is a removed option, and its text is
`othrys.apps.ai.context.text`.

## Ollama

`othrys.apps.ai.ollama` runs the Ollama server on the address in `host` and
the port in `port`, `127.0.0.1` and `11434` by default. It pulls the models in
`loadModels` at start and persists them. `acceleration` picks the
package, and its default follows the host. An `othrys.hardware.nvidia` host
gets `ollama-cuda`, any other host with `hardware.graphics.enable` gets
`ollama-vulkan`, which runs on AMD and Intel cards, and a host without graphics
gets `ollama-cpu`. An AMD host that wants ROCm sets `acceleration = "rocm"`.
The CUDA build is unfree and pulls the CUDA toolkit, so a host without an
NVIDIA card never gets it by default.

`host = "0.0.0.0"` or `host = "::"` serves every address. Ollama asks for no
credentials, so anything that reaches the port can run models. On NixOS the
module opens no port in the firewall, so while `networking.firewall.enable`
is on the host opens it where it wants clients, for example with
`networking.firewall.interfaces.<name>.allowedTCPPorts`. On nix-darwin nothing
closes the port, so an address other than loopback is reachable from the
network as soon as the agent starts.

```nix
othrys.apps.ai.ollama = {
  enable = true;
  host = "0.0.0.0";
};
networking.firewall.interfaces.eth0.allowedTCPPorts = [11434];
```

The module sets `OLLAMA_HOST` for the user, so the `ollama` client finds the
server. When the server binds every address, the variable points at the
loopback of that family, `127.0.0.1` for `0.0.0.0` and `[::1]` for `::`, and
otherwise at the address the server binds. An IPv6 address is put in
brackets for the server and the client alike, since both upstream modules
join the host and the port with a bare colon. The module hands the server
both values as defaults, and the variable is read from the server's merged
values, so a host that sets `services.ollama.host` or `services.ollama.port`
itself still points the client at the server.

On nix-darwin, which has no Ollama service, the server is Home Manager's
`services.ollama`. It runs as the user's launchd agent on the same `host` and
`port` and reaches the user through `darwinModules.home`, so a host without a
managed account gets no server. The CUDA, ROCm and Vulkan variants are
Linux only, so `acceleration` defaults to `"cpu"` there, which names
nixpkgs' one darwin build, and any other value is refused.
Home Manager's agent pulls no models, so `loadModels` is refused as well,
and the user runs `ollama pull`.

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
