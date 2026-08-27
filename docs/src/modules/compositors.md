# Compositors (Hyprland)

Hyprland Wayland compositor with automatic workspace generation, window rules, and UWSM integration.

## Config format

Hyprland 0.5x reads Lua (`~/.config/hypr/hyprland.lua`); hyprlang is the legacy
provider. The module pins `configType = "lua"` and expresses every setting as
an `hl.*` call, so option values are structured attrsets rather than the
comma-separated hyprlang strings they used to be. Monitors, workspace rules
and window rules all take the shape of the `hl.*` function that consumes them.
Key chords use Hyprland's `+`-separated syntax (`$mainMod + SHIFT + H`), where
`$mainMod` expands to a Lua local carrying the `mainMod` option.

Two knock-on effects worth knowing:

- `hyprctl dispatch` is a shorthand for `hl.dispatch(...)` under the Lua
  provider, so its argument is a Lua expression:
  `hyprctl dispatch 'hl.dsp.exit()'`, not `hyprctl dispatch exit`.
- Home Manager also writes `~/.config/hypr/.luarc.json`, pointing the Lua
  language server at the compositor's own `hl.*` stubs for editor completion.

## Options

```nix
{{#include ../../../modules/desktop/compositors/hyprland.nix:hyprland-options}}
```

## Keybindings

```nix
{{#include ../../../modules/desktop/compositors/hyprland.nix:hyprland-keybindings}}
```

### Quick Reference

| Binding | Action |
|---------|--------|
| `Super + 1-0` | Switch workspace |
| `Super + Shift + 1-0` | Move window to workspace |
| `Super + H/J/K/L` | Focus left/down/up/right |
| `Super + Shift + H/J/K/L` | Swap window |
| `Super + Q` | Kill window |
| `Super + Return` | Terminal |
| `Super + F` | Browser |
| `Super + M` | Fullscreen |
| `Super + V` | Toggle floating |
| `Super + S` | Scratchpad |
| `Print` | Screenshot (full) |
| `Super + Print` | Screenshot (region) |

## Window Rules

```nix
{{#include ../../../modules/desktop/compositors/hyprland.nix:hyprland-windowrules}}
```

## Monitor Configuration

Monitors are configured per-host as `hl.monitor()` specs. `output` is required;
`mode`, `position`, and `scale` default to `preferred`/`auto`/`auto`, and any
other `hl.monitor()` field (`vrr`, `transform`, `mirror`, `disabled`, ...)
passes through:

```nix
othrys.desktop.compositors.hyprland.monitors = [
  {
    output = "DP-1";
    mode = "1920x1080@360";
    position = "0x0";
    scale = "1";
  }
  {output = "HDMI-A-1";} # preferred mode, auto position/scale
];
```

An empty `output` is the catch-all rule matching every unnamed connector, so it is the
module default (`[{output = "";}]`) and the usual external-display fallback.

Workspaces auto-generate based on monitor count:

- **Single monitor**: all 10 workspaces on it
- **Dual monitor**: workspaces 1-5 on primary, 6-10 on secondary

Named monitors get a `monitor:` binding in the generated `hl.workspace_rule()`
calls, while the catch-all rule does not, since pinning workspaces to it is
meaningless. Set `workspaces` to override the generated rules wholesale.
