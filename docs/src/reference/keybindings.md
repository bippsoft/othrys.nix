# Keybindings

Keybinding reference for the two compositors. The tables show the **defaults**.
Every action's chord is an option, and setting one to `null` drops the bind. The
two modules share a chord wherever the action exists in both, so the same hand
positions work in either session.

## Hyprland

Chords live under `othrys.desktop.compositors.hyprland.binds.*`. `$mainMod` is the `mainMod` option (default `SUPER`), and numbered-workspace binds are toggled by `numberedWorkspaceBinds`.

Chords use Hyprland's `+`-separated syntax, e.g. `$mainMod + SHIFT + H` or a bare `Print`. Add binds the module does not curate with `extraBinds`, whose `dispatcher` is a raw Lua expression:

```nix
othrys.desktop.compositors.hyprland.extraBinds = [
  {
    key = "$mainMod + CTRL + 1";
    dispatcher = ''hl.dsp.focus({ monitor = "DP-1" })'';
  }
];
```

### Workspace

| Binding | Action |
|---------|--------|
| `Super + 1-0` | Switch to workspace 1-10 |
| `Super + Shift + 1-0` | Move window to workspace 1-10 |
| `Super + Ctrl + Left/Right` | Cycle workspaces |
| `Super + Mouse wheel` | Cycle workspaces |
| `Super + S` | Toggle scratchpad |
| `Super + Shift + S` | Move to scratchpad |

### Focus & Window Management

| Binding | Action |
|---------|--------|
| `Super + H/J/K/L` | Focus left/down/up/right |
| `Super + Shift + H/J/K/L` | Swap window left/down/up/right |
| `Super + Q` | Kill active window |
| `Super + M` | Fullscreen |
| `Super + V` | Toggle floating |
| `Super + P` | Pseudo-tile |
| `Super + Y` | Pin window |
| `Super + Shift + E` | Exit Hyprland |

### Mouse

| Binding | Action |
|---------|--------|
| `Super + Left click drag` | Move window |
| `Super + Right click drag` | Resize window |

### Applications

| Binding | Action |
|---------|--------|
| `Super + Return` | Terminal (the `terminal` option) |
| `Super + F` | Browser (the `browser` option) |

Launcher, emoji-picker, and color-picker binds are added by the [ashell module](../modules/desktop.md#ashell) when enabled.

### Media

| Binding | Action |
|---------|--------|
| `Volume Up/Down` | Adjust volume (5%) |
| `Volume Mute` | Toggle mute |
| `Mic Mute` | Toggle mic mute |
| `Brightness Up/Down` | Adjust brightness (10%) |
| `Media Next/Prev/Play` | Player control |

### Screenshots

| Binding | Action |
|---------|--------|
| `Print` | Full screenshot → `screenshots.directory` (default `~/Pictures/Screenshots/`) |
| `Super + Print` | Region screenshot → file |
| `Super + Shift + Print` | Region screenshot → clipboard |

### Source

```nix
{{#include ../../../modules/desktop/compositors/hyprland.nix:hyprland-keybindings}}
```

## Niri

Chords live under `othrys.desktop.compositors.niri.binds.*` and use niri's
syntax, `Mod+Shift+H` or a bare `Print`. `Mod` is the Super key in a session
started from a greeter. Niri arranges windows in columns on a strip that
scrolls sideways, so the horizontal binds act on columns and the vertical ones
on the windows inside a column. Add binds the module does not curate with
`extraBinds`, in the format of `programs.niri.settings.binds`:

```nix
othrys.desktop.compositors.niri.extraBinds = {
  "Mod+T".action.spawn = "thunderbird";
};
```

### Workspace

| Binding | Option | Action |
|---------|--------|--------|
| `Mod + 1-9` | `numberedWorkspaceBinds` | Focus workspace 1-9 |
| `Mod + Shift + 1-9` | `numberedWorkspaceBinds` | Move the column to workspace 1-9 |
| `Mod + Ctrl + Left` | `binds.workspacePrev` | Previous workspace |
| `Mod + Ctrl + Right` | `binds.workspaceNext` | Next workspace |
| `Mod + S` | `binds.overview` | Toggle the overview |

Niri has no scratchpad, so `Mod + S` opens the overview where Hyprland toggles
its scratchpad.

### Focus & Window Management

| Binding | Option | Action |
|---------|--------|--------|
| `Mod + H/L` | `binds.focusLeft`, `binds.focusRight` | Focus the column to the left or right |
| `Mod + J/K` | `binds.focusDown`, `binds.focusUp` | Focus the window below or above |
| `Mod + Shift + H/L` | `binds.moveLeft`, `binds.moveRight` | Move the column left or right |
| `Mod + Shift + J/K` | `binds.moveDown`, `binds.moveUp` | Move the window down or up |
| `Mod + Q` | `binds.killActive` | Close the active window |
| `Mod + M` | `binds.fullscreen` | Toggle fullscreen |
| `Mod + P` | `binds.maximizeColumn` | Maximize the column |
| `Mod + V` | `binds.toggleFloating` | Toggle floating |
| `Mod + Shift + E` | `binds.exit` | Quit niri |

### Applications

| Binding | Option | Action |
|---------|--------|--------|
| `Mod + Return` | `binds.terminal` | Terminal (the `terminal` option) |
| `Mod + F` | `binds.browser` | Browser (the `browser` option) |

The [ashell module](../modules/desktop.md#ashell) adds `Mod + D` for the
launcher, `Mod + Shift + D` for the run prompt and `Mod + E` for the emoji
picker. The color picker is Hyprland only.

### Media

These keys also work while the session is locked. They have no option and are
replaced through `extraBinds`.

| Binding | Action |
|---------|--------|
| `Volume Up/Down` | Adjust volume (5%) |
| `Volume Mute` | Toggle mute |
| `Media Play/Pause` | Toggle playback |

### Screenshots

| Binding | Option | Action |
|---------|--------|--------|
| `Print` | `binds.screenshot` | Open niri's interactive screenshot UI |
| `Mod + Print` | `binds.screenshotScreen` | Screenshot the full screen |
| `Mod + Shift + Print` | `binds.screenshotWindow` | Screenshot the focused window |

Screenshots are saved into `screenshots.directory` (default
`~/Pictures/Screenshots`).
