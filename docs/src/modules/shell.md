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
- Toggleable alias presets (`aliasPresets.{nix,navigation,modernUnix,editor,git,python,jvm,ansible,opentofu,node,docker,clipboard}`, all on by default except `clipboard`, which follows `othrys.desktop.graphical`) plus `extraAliases` for consumer additions
- Persistence for history and the zoxide database. History is kept in
  `~/.local/share/zsh/history`, and the module persists that directory rather
  than the file, since zsh saves history by renaming a temporary file over
  `HISTFILE` and a rename onto a bind-mounted file fails. The direnv allow
  database is persisted by `othrys.apps.development`, which owns direnv.

Enabling zsh makes it the primary user's login shell through
`othrys.system.users.defaultShell`, which a host overrides when it wants
another. The `nix` preset's `nix-clean` keeps a week of generations, so a
rollback target survives it.

The default editor behind `EDITOR`/`VISUAL`, git's `core.editor`, and the `v`/`vim`/`vi` aliases is `othrys.system.defaultEditor` (default `vim`). The variables are set once, through `environment.variables`, and an editor module such as nixvim makes itself the default with `mkDefault` when enabled.

## Starship

Minimal, fast prompt with Git integration. Its colours come from `othrys.theme.palette`. On a host with no palette the layout is the same and each colour is an ANSI name, which the terminal resolves.
