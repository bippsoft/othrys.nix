# Keybindings

Hyprland keybinding reference. The table shows the **defaults**, and every action's chord is an option under `othrys.desktop.compositors.hyprland.binds.*` (set to `null` to drop a bind), `$mainMod` is the `mainMod` option (default `SUPER`), and numbered-workspace binds are toggled by `numberedWorkspaceBinds`.

Chords use Hyprland's `+`-separated syntax, e.g. `$mainMod + SHIFT + H` or a bare `Print`. Add binds the module does not curate with `extraBinds`, whose `dispatcher` is a raw Lua expression:

```nix
othrys.desktop.compositors.hyprland.extraBinds = [
  {
    key = "$mainMod + CTRL + 1";
    dispatcher = ''hl.dsp.focus({ monitor = "DP-1" })'';
  }
];
```

## Workspace

| Binding | Action |
|---------|--------|
| `Super + 1-0` | Switch to workspace 1-10 |
| `Super + Shift + 1-0` | Move window to workspace 1-10 |
| `Super + Ctrl + Left/Right` | Cycle workspaces |
| `Super + Mouse wheel` | Cycle workspaces |
| `Super + S` | Toggle scratchpad |
| `Super + Shift + S` | Move to scratchpad |

## Focus & Window Management

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

## Mouse

| Binding | Action |
|---------|--------|
| `Super + Left click drag` | Move window |
| `Super + Right click drag` | Resize window |

## Applications

| Binding | Action |
|---------|--------|
| `Super + Return` | Terminal (the `terminal` option) |
| `Super + F` | Browser (the `browser` option) |

Launcher, emoji-picker, and color-picker binds are added by the [ashell module](../modules/desktop.md#ashell) when enabled.

## Media

| Binding | Action |
|---------|--------|
| `Volume Up/Down` | Adjust volume (5%) |
| `Volume Mute` | Toggle mute |
| `Mic Mute` | Toggle mic mute |
| `Brightness Up/Down` | Adjust brightness (10%) |
| `Media Next/Prev/Play` | Player control |

## Screenshots

| Binding | Action |
|---------|--------|
| `Print` | Full screenshot → `screenshots.directory` (default `~/Pictures/Screenshots/`) |
| `Super + Print` | Region screenshot → file |
| `Super + Shift + Print` | Region screenshot → clipboard |

## Source

```nix
{{#include ../../../modules/desktop/compositors/hyprland.nix:hyprland-keybindings}}
```
