# Desktop

Desktop environment modules under `othrys.desktop.*`. Handles compositors, status bar, and session management.

Theming (Stylix) has moved to `othrys.system.stylix`, see [Theming](../guides/theming.md).

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Ashell | `othrys.desktop.ashell` | GPU-accelerated status bar with Stylix theming |
| Hyprland | `othrys.desktop.compositors.hyprland` | Wayland compositor (dynamic tiling) |
| Niri | `othrys.desktop.compositors.niri` | Wayland compositor (scrollable tiling) |
| Idle | `othrys.desktop.idle` | Staged idle management (dim, lock, screen off, suspend) |
| Login | `othrys.desktop.login` | greetd login manager (tuigreet or cosmic-greeter) |
| Night light | `othrys.desktop.nightLight` | Color temperature shifting (gammastep) |
| Noctalia | `othrys.desktop.noctalia` | All-in-one Wayland shell (bar, launcher, notifications, lock, wallpaper) |
| UWSM | `othrys.desktop.uwsm` | Systemd session management for Wayland |

## Ashell

Status bar for Hyprland or Niri (either compositor satisfies its assertion, and lock/logout commands adapt automatically). Installed from the `ashell` flake input, configured via a generated `~/.config/ashell/config.toml` with Stylix colors injected at build time. Hot-reloads on config changes.

Bundles: wofi (launcher), cliphist/wl-clipboard (clipboard), pavucontrol (audio), hyprlock (lock screen), hyprpicker (color picker), rofimoji (emoji picker).

### Options

```nix
{{#include ../../../modules/desktop/ashell/default.nix:ashell-options}}
```

### Keybindings (via Hyprland)

| Binding | Action |
|---------|--------|
| `Super + D` | App launcher (wofi drun) |
| `Super + Shift + D` | Command runner (wofi run) |
| `Super + E` | Emoji picker (rofimoji) |
| `Super + Shift + C` | Color picker to clipboard (hyprpicker) |

## Compositors

See [Compositors (Hyprland)](./compositors.md) for the full Hyprland reference.

```nix
othrys.desktop.compositors.hyprland = {
  enable = true;
  monitors = [
    {output = "eDP-1";}
  ];
};
```

### Niri

Scrollable-tiling compositor via [niri-flake](https://github.com/sodiboo/niri-flake)
(typed, build-time-validated config, self-contained, with no extra upstream import
for consumers). The option surface mirrors hyprland where concepts map (chords,
terminal/browser, outputs, touchpad, screenshots) and is niri-native where they
do not (columns scroll, and `Mod+S` opens the overview). Niri manages its own
systemd session: point the login module at it with
`othrys.desktop.login.sessionCommand = "niri-session"`. Stylix themes borders
and cursor through niri-flake's auto-imported target.

```nix
othrys.desktop.compositors.niri = {
  enable = true;
  outputs."DP-1".mode = {
    width = 1920;
    height = 1080;
    refresh = 144.0;
  };
};
othrys.desktop.login.sessionCommand = "niri-session";
```

#### Options

```nix
{{#include ../../../modules/desktop/compositors/niri.nix:niri-options}}
```

## UWSM

Universal Wayland Session Manager. When enabled, Hyprland registers as a UWSM-managed compositor for proper systemd session integration.

```nix
othrys.desktop.uwsm.enable = true;
```

## Noctalia

[Noctalia](https://noctalia.dev/) is a native Wayland desktop shell: bar,
launcher, control center, notifications, lock screen, wallpaper, clipboard
history, and OSDs in one layer (no Qt/GTK). Exclusive with [Ashell](#ashell), so
one shell layer per host.

Configured through upstream's home-manager module: nix-declared defaults land
in a build-time-validated `config.toml`, while the in-shell settings GUI
layers its overrides in `~/.local/state/noctalia` (persisted under
impermanence), so both coexist. Theming defaults to a custom palette
generated from the Stylix base16 scheme, while `theme.source` escapes to noctalia's
builtin/wallpaper/community engines. Launcher/clipboard/session/lock chords
are written into whichever compositor (Hyprland, Niri) is enabled, dispatched
over noctalia's IPC.

### Options

```nix
{{#include ../../../modules/desktop/noctalia.nix:noctalia-options}}
```

### Usage

```nix
othrys.desktop.noctalia = {
  enable = true;
  weather.enable = true;
  location.address = "Toronto, ON";
  bar.widgets.center = ["clock" "media"];
};
```

## Idle

Staged idle policy via hypridle (ext-idle-notify, which works on Hyprland and
Niri): optional backlight dim, lock (via the shared
`othrys.desktop.lockCommand` signal), screen off (compositor-flavored DPMS),
and optional suspend. Conflicts with Noctalia, which manages idle itself.

### Options

```nix
{{#include ../../../modules/desktop/idle.nix:idle-options}}
```

## Night light

Color temperature shifting via gammastep. Provide coordinates from the host
for solar scheduling, or leave them unset to resolve location through
geoclue. Conflicts with Noctalia's built-in night light.

### Options

```nix
{{#include ../../../modules/desktop/night-light.nix:night-light-options}}
```
