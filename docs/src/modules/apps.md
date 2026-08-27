# Applications

Application modules under `othrys.apps.*`, split into CLI and GUI categories.

Application modules curate each app's integration (persistence, theming, sane settings). Personal choices (search engines, wordmarks, tokens) are options the consuming fleet sets.

## CLI Applications (`modules/apps/cli/`)

No desktop environment required, so these are usable on servers and headless systems.

| Module | Option | Description |
|--------|--------|-------------|
| Nixvim | `othrys.apps.nixvim` | Neovim configured via Nix (sub-modules for plugins/languages) |
| Development | `othrys.apps.development` | Development tools bundle |
| GitHub CLI | `othrys.apps.gh` | GitHub CLI with persistence |
| Yazi | `othrys.apps.yazi` | Terminal file manager |
| Comma | `othrys.apps.comma` | Run uninstalled programs with nix-index |

## GUI Applications (`modules/apps/gui/`)

Require a desktop environment.

| Module | Option | Description |
|--------|--------|-------------|
| Ghostty | `othrys.apps.ghostty` | Terminal emulator with rich options |
| Kitty | `othrys.apps.kitty` | Alternative terminal emulator |
| Floorp | `othrys.apps.floorp` | Firefox-based browser |
| VS Code | `othrys.apps.vscode` | Visual Studio Code |
| Vesktop | `othrys.apps.vesktop` | Discord client |
| Signal | `othrys.apps.signal` | Signal messenger |
| OBS | `othrys.apps.obs` | Screen recording/streaming |
| Picard | `othrys.apps.picard` | MusicBrainz tagger |
| Plexamp | `othrys.apps.plexamp` | Plex music player |
| RustDesk | `othrys.apps.rustdesk` | Remote desktop |
| LocalSend | `othrys.apps.localsend` | Local file sharing |
| MPV | `othrys.apps.mpv` | Media player |

See also: [Gaming](./gaming.md), [AI Assistants](./ai.md)

For the anatomy of a fully-featured module, see the login manager example in [Module System](../architecture/module-system.md).
