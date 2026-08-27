# Shell

Shell modules under `othrys.system.shell.*`. Located in `modules/system/shell/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Zsh | `othrys.system.shell.zsh` | Primary shell with plugins, completions, aliases |
| Bash | `othrys.system.shell.bash` | Fallback shell |
| Starship | `othrys.system.shell.starship` | Cross-shell prompt |

## Zsh

Full-featured Zsh with:

- Plugin management (syntax highlighting, autosuggestions, completions)
- Direnv integration for automatic dev shell activation
- Zoxide for smart directory jumping
- Toggleable alias presets (`aliasPresets.{nix,navigation,modernUnix,editor,git,python,jvm,ansible,opentofu,node,docker,clipboard}`, all on by default) plus `extraAliases` for consumer additions
- Persistence for history, zoxide database, and direnv state

The default editor behind `EDITOR`/`VISUAL`, git's `core.editor`, and the `v`/`vim`/`vi` aliases is `othrys.system.defaultEditor` (default `vim`).

## Starship

Minimal, fast prompt with Git integration. Themed by Stylix.
