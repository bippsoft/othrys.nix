# Applications

Application modules under `othrys.apps.*`, split into CLI and GUI categories.

Application modules curate each app's integration (persistence, theming, sane settings). Personal choices (search engines, wordmarks, tokens) are options the consuming fleet sets.

## CLI Applications (`modules/apps/cli/`)

No desktop environment required, so these are usable on servers and headless systems.

| Module | Option | Description |
|--------|--------|-------------|
| Nixvim | `othrys.apps.nixvim` | Neovim configured via Nix (sub-modules for plugins/languages) |
| Languages | `othrys.apps.languages.<name>` | Per-language toolchains shared by the PATH and both editors |
| Development | `othrys.apps.development` | Development tools bundle, direnv with its allow database persisted |
| GitHub CLI | `othrys.apps.gh` | `gh` with its settings, the git credential helper, a token file for a headless host and read-only commands pre-approved for Claude Code |
| Yazi | `othrys.apps.yazi` | Terminal file manager |
| Comma | `othrys.apps.comma` | Run uninstalled programs with nix-index, whose `command-not-found` handler names the package for a missing command |

The assistant modules under `modules/apps/cli/ai/` are listed on the
[AI Assistants](./ai.md) page.

## GUI Applications (`modules/apps/gui/`)

Require a desktop environment.

| Module | Option | Description |
|--------|--------|-------------|
| Ghostty | `othrys.apps.ghostty` | Terminal emulator with rich options |
| Kitty | `othrys.apps.kitty` | Alternative terminal emulator |
| Floorp | `othrys.apps.floorp` | Firefox-based browser |
| VSCodium | `othrys.apps.vscode` | VSCodium editor, wired to the shared language toolchains |
| Vesktop | `othrys.apps.vesktop` | Discord client with Wayland support |
| Discord | `othrys.apps.discord` | Official Discord client, with `~/.config/discord` persisted at mode `0700` |
| IDEA | `othrys.apps.idea` | IntelliJ IDEA with a curated plugin catalogue. Requires `othrys.apps.languages.java` |
| Signal | `othrys.apps.signal` | Signal messenger |
| OBS | `othrys.apps.obs` | Screen recording/streaming. Enables `othrys.services.virtualcamera`, and builds with CUDA when `othrys.hardware.nvidia` is on |
| Picard | `othrys.apps.picard` | MusicBrainz tagger |
| Plexamp | `othrys.apps.plexamp` | Plex music player |
| RustDesk | `othrys.apps.rustdesk` | Remote desktop client. Persists `~/.config/rustdesk`, and `forceX11` starts the launcher through XWayland |
| LocalSend | `othrys.apps.localsend` | Local file sharing |
| MPV | `othrys.apps.mpv` | Media player |

The modules under `modules/apps/gui/gaming/` are listed on the
[Gaming](./gaming.md) page.

### GitHub CLI

`othrys.apps.gh` installs `gh` and writes its `config.yml`. `gitProtocol`,
`editor` and `aliases` cover the common keys, and `settings` takes any other
key and is merged over them, so a key set there wins. `editor` follows
`othrys.system.defaultEditor`. `extensions` takes a list of packages.

```nix
othrys.apps.gh = {
  enable = true;
  aliases.co = "pr checkout";
  settings.pager = "less -FRX";
};
```

The module does not log in. On a desktop, run `gh auth login` once. It runs
GitHub's OAuth device flow, which shows a code to enter in a browser, and it
stores the resulting token in the Secret Service keyring when one is running.
[`othrys.desktop.keyring`](./desktop.md#keyring) provides that keyring on a
graphical host. Without one `gh` falls back to a plain file,
`~/.config/gh/hosts.yml`. Under impermanence `~/.config/gh` is persisted at
mode 0700 for the primary user, which keeps the account name in both cases and
the token in the second.

With `credentialHelper.enable`, which is on by default, git asks `gh` for
credentials on the URLs in `credentialHelper.hosts`. A clone, fetch or push
over HTTPS then uses the `gh` login, and no second credential is stored for
git. A remote reached over SSH is not affected.

A headless host has no browser for the device flow and no keyring to hold the
result. `tokenFile` names a runtime path that a secrets provider writes, and
the file has to be readable by the primary user.

```nix
othrys.apps.gh = {
  enable = true;
  gitProtocol = "https";
  tokenFile = "/run/secrets/gh-token";
};
```

`gh` reads a token only from the `GH_TOKEN` environment variable, so with
`tokenFile` set the `gh` on the PATH is a wrapper around the real program. The
wrapper reads the file, sets `GH_TOKEN` in its own process and replaces that
process with `gh`. It guarantees three things:

- **The Nix store** holds the path of the file and never its content, since
  the option refuses a path literal and a store path.
- **The shell** never has the variable, so no other program started from it
  inherits the token.
- **No process argument** carries the token, so it does not appear in the
  process list.

The token is in the environment of the running `gh` and of the programs `gh`
starts, such as git, the editor and an extension. The completions and the man
pages are the ones `gh` ships. The git credential helper runs the wrapper as
well, so git over HTTPS works on such a host without a login. A `GH_TOKEN` that
is already set is kept. When the file is missing or unreadable the wrapper says
so on stderr and runs `gh` without it, so `gh auth status` reports the login
the host really has.

When `othrys.apps.ai.claude-code` is enabled as well, the module adds the
read-only `gh` commands to the Claude Code allow-list, and an agent reads
GitHub without a prompt. The entries are `gh issue view`, `gh issue list`,
`gh pr view`, `gh pr list`, `gh pr diff`, `gh pr checks`, `gh run view`,
`gh run list`, `gh repo view`, `gh release view`, `gh release list` and
`gh search`, each in the `Bash(gh pr view:*)` form. A command that creates,
edits, merges, closes or comments stays prompted, and so do `gh auth` and
`gh api`, since `gh api` sends any request. `claudeCode.allowReadOnly = false`
leaves the entries out. The lists are a convenience and not a boundary, as
[AI Assistants](./ai.md#what-the-claude-code-permission-lists-are-for)
explains.

### Kitty

Remote control is accepted on a unix socket only. Each kitty process listens
on `$XDG_RUNTIME_DIR/kitty-<pid>.sock`, a directory other users cannot read,
and `kitty @` inside the terminal finds it through `KITTY_LISTEN_ON`. Control
sequences written to the terminal itself are ignored, so the output of a
program, or of a remote host over SSH, cannot drive the windows.

`extraSettings` takes `kitty.conf` keys and is merged over the defaults the
module writes, so a key set there wins.

```nix
othrys.apps.kitty = {
  enable = true;
  extraSettings = {
    scrollback_lines = "50000";
    tab_bar_style = "fade";
  };
};
```

### Ghostty

Ghostty measures its scrollback in bytes and not in lines.
`scrollbackLimit` is that byte count for each terminal surface, and it
defaults to Ghostty's own 10 MB. It replaces `scrollbackLines`, whose default
of 10000 was written as 10000 bytes, about a hundred lines of plain text.
Setting the old option now fails with a message naming the new one.

```nix
othrys.apps.ghostty = {
  enable = true;
  scrollbackLimit = 50000000;
};
```

`extraSettings` takes Ghostty config keys and is merged over what the module
writes. A value is a string, a number, a boolean, or a list of those for a key
that repeats, such as `keybind`. A nested attribute set is refused, since the
config file is flat.

### Vesktop

`settings` is written to Vesktop's `settings.json` over the module defaults
and accepts any JSON value.

## Floorp

The browser force-installs a curated extension set, Sidebery, Bitwarden and
uBlock Origin, through `othrys.apps.floorp.extensions`.
Each entry names a versioned download URL and its hash, so the file is
fetched at build time and installed from the Nix store rather than pulled
from the add-on site at first start. Replace the set to drop one. A
definition replaces the whole default, so a host that wants one more
extension merges it over `options.othrys.apps.floorp.extensions.default`.
The option's example does that for Violentmonkey, which is not in the
default set because a userscript manager runs whatever scripts it is given
with page access on the sites they match. The
built-in password manager is off beside Bitwarden
(`builtinPasswordManager`), tracking protection exempts nothing until a host
lists sites in `trackingProtectionExemptions`, and the theme follows
`othrys.theme.polarity`. The browser chrome is styled from
`othrys.theme.palette`, and on a host with no palette no stylesheet is written.

`search.extraEngines` adds search engines over the curated set. Each engine
is an attribute set of JSON values in the shape Home Manager documents for
`programs.firefox.profiles.<name>.search.engines`.

## VSCodium

`othrys.apps.vscode.mutableExtensionsDir` decides whether the editor can
install extensions itself. With `true`, the default and Home Manager's own,
`~/.vscode-oss/extensions` is a real directory. The extensions the
configuration names are linked into it, and one installed by hand from Open VSX
sits beside them, persists with `.vscode-oss` and updates itself. With `false`
the directory is a link into the Nix store, so the editor runs exactly the set
the configuration names and an install from the editor fails. A host that
switches to `false` removes the existing directory first, since Home Manager
does not replace a directory it did not create.

## Language Toolchains (`modules/apps/languages/`)

`othrys.apps.languages.<name>.enable` is the one signal that a host develops in
a language. Each entry holds a `server`, a `formatter` and a list of
`extraTools`, and enabling it installs all three on the primary user's PATH.
Nixvim and VSCodium read the same entry, so neither editor carries a toolchain
of its own.

| Language | Server | Formatter | Extra tools |
|----------|--------|-----------|-------------|
| `bash` | `bash-language-server` | `shfmt` | `shellcheck` |
| `go` | `gopls` | `gofmt` from `go` | |
| `java` | none | `google-java-format` | `jdk21`, `maven`, `gradle` |
| `json` | `vscode-langservers-extracted` | `prettier` | |
| `lua` | `lua-language-server` | `stylua` | |
| `nix` | `nil` | `alejandra` | |
| `python` | `basedpyright` | `ruff` | |
| `rust` | `rust-analyzer` | `rustfmt` | |
| `typescript` | `typescript-language-server` | `prettier` | `typescript` |
| `yaml` | `yaml-language-server` | `prettier` | |

JSON and YAML are entries of their own. A host that edits YAML without writing
TypeScript enables `yaml` alone, and enabling `typescript` configures neither of
them.

### Overriding a tool

Both editors name the registry package by its store path, so an override reaches
them and the PATH together.

```nix
othrys.apps.languages.nix = {
  enable = true;
  formatter = pkgs.nixfmt;
};
```

Nixvim formats through conform.nvim, which keeps a definition with the right
arguments for each formatter it knows. The module selects that definition by the
executable name of the package and sets its command to the store path. The
override above therefore runs under conform's `nixfmt` definition and not under
the `alejandra` one with a different binary behind it. A tool conform has no
definition for is run with no arguments and the buffer on stdin. Two languages
whose formatters share an executable name share one definition, so `typescript`,
`json` and `yaml` must hold the same `prettier` package or evaluation reports
the conflicting commands.

VSCodium takes a binary only where an extension has a setting for one. The
table shows what each extension reads from the registry.

| Language | From the registry | Bundled by the extension or the editor |
|----------|-------------------|-----------------------------------------|
| `bash` | `shfmt`, `shellcheck` | `bash-language-server` |
| `go` | `gopls`, the formatter | |
| `java` | | `jdtls` |
| `json` | `prettier` | the JSON language service |
| `lua` | `lua-language-server` | formatting, done by the server |
| `nix` | `nil`, the formatter | |
| `python` | `ruff` | `basedpyright` |
| `rust` | `rust-analyzer` | |
| `typescript` | `prettier` | the TypeScript language service |
| `yaml` | `prettier` | `yaml-language-server` |

The bash extensions read `shellcheck` out of `extraTools`, found by its
executable name. A host that removes it from the list gets no shellcheck path in
either extension. The prettier and ruff settings apply only while the formatter
is still that tool, since each extension can drive nothing else. A host that
replaces one of them also chooses its own `editor.defaultFormatter` through
`othrys.apps.vscode.userSettings`.

### A language with no server

`server` accepts `null`, and `java` ships that way. An editor then configures no
external server for the language. Nixvim enables no LSP client for it, while
VSCodium omits the server path and the extension runs whatever it bundles. For
Nix the extension has no bundled server, so the language server is switched off
and formatting continues to work.

See also: [Gaming](./gaming.md), [AI Assistants](./ai.md)

For the anatomy of a fully-featured module, see the login manager example in [Module System](../architecture/module-system.md).
