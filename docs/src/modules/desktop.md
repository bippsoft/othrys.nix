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

Status bar for Hyprland or Niri. Either compositor satisfies its assertion, and the lock and logout commands follow the session that is running, as described under [Sessions](#sessions). Installed from the `ashell` flake input, configured via a generated `~/.config/ashell/config.toml` with Stylix colors injected at build time. Hot-reloads on config changes.

The module installs wofi as the launcher, rofimoji as the emoji picker, the
locker of each enabled compositor and, on Hyprland, hyprpicker. The audio
buttons open pavucontrol, which `othrys.hardware.audio` installs on a graphical
host.

The clock shows no weather until `weatherLocation` is set. With the default of
`null` the key is left out of the config and the bar makes no forecast request.
The value is the TOML ashell reads, and it is identity-shaped, so the host sets
it.

```nix
othrys.desktop.ashell.weatherLocation = "{ Coordinates = [40.7128, -74.0060] }";
```

The clipboard button reads a history that cliphist keeps, fed by a Home Manager
user service on Hyprland and on Niri alike. The history is a plain file under
`~/.cache/cliphist` and holds everything copied, apart from entries a password
manager marks as sensitive. It keeps `clipboard.maxItems` entries, 100 by
default, and the default lock command wipes it each time the session locks. A
host that replaces `othrys.desktop.lockCommand` takes over that wipe.
`clipboard.enable = false` removes the service, the button and the wipe. A
Hyprland host without ashell no longer records a clipboard history at all.

The settings group at the right of the bar follows the host. A desktop shows the
idle inhibitor, peripheral batteries, audio and the microphone. A host with
`othrys.hardware.laptop.enable` also shows its own battery, the screen
brightness and the network, shows Bluetooth when `hardware.bluetooth.enable`
holds, and shows the power profile when `services.power-profiles-daemon.enable`
holds, which leaves it out on a host that uses TLP. On a laptop the settings menu
keeps its airplane mode button, and the clock drops its seconds so the bar does
not redraw once a second on battery. `indicators`, `airplaneButton` and
`clockFormat` override each of these.

The battery indicator reads UPower, which the laptop module enables.

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

## Sessions

A host can enable both compositors and let the greeter choose between them, so
an enabled module does not say which compositor is running. The commands that
talk to a compositor are therefore chosen at run time on such a host. The
screen-off and screen-on stages of the idle module, ashell's logout button and
the default lock command each become a small script that reads
`XDG_CURRENT_DESKTOP` and calls `niri msg` and `swaylock` in a Niri session or
`hyprctl` and `hyprlock` in a Hyprland one. A host with one compositor gets the
plain command with no script in between. `modules/desktop/session.nix` holds
the test, and a module that adds a compositor command builds it there.

Both lockers and both PAM services are installed on a host with both
compositors, since each session runs its own.

Enabling either compositor installs Nautilus as the file manager, in the
primary user's packages.

## Compositors

See [Compositors (Hyprland)](./compositors.md) for the full Hyprland reference.

The `browser` option of both compositors defaults to `floorp` when
`othrys.apps.floorp` is enabled. Without it the default stays `firefox`, which
no othrys module installs, so a host with another browser sets the option.
Hyprland no longer exports `TERM` to the session, and each terminal sets its
own.

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
systemd session, and the login module starts `niri-session` by default on a
host where niri is the only compositor. Stylix themes borders and cursor
through niri-flake's auto-imported target.

```nix
othrys.desktop.compositors.niri = {
  enable = true;
  outputs."DP-1".mode = {
    width = 1920;
    height = 1080;
    refresh = 144.0;
  };
};
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

Noctalia stores credentials in the Secret Service and the tray applications it
hosts expect one, so the module enables gnome-keyring on every Noctalia host.
With `othrys.desktop.login` the keyring is unlocked by the login password, and
under impermanence `~/.local/share/keyrings` is persisted.

One wallpaper engine runs. On a Hyprland host with
`othrys.system.stylix.wallpaper` set, Stylix would start hyprpaper beside
Noctalia's own engine. Noctalia's is kept, since its picker and its
wallpaper-generated palettes depend on it, and hyprpaper is turned off. The
Stylix wallpaper still appears, as Noctalia's default image. Setting
`wallpaper.enable = false` hands the wallpaper back to hyprpaper.

`settings` takes the tables and keys of noctalia's `config.toml` and is
deep-merged over the config the module generates, so a key set there replaces
what an option would have written.

```nix
othrys.desktop.noctalia.settings = {
  osd.position = "bottom_center";
  notification.show_actions = false;
  shell.show_location = false;
};
```

The merge covers only what this module generates. With
`theme.source = "stylix"` the Stylix target writes `theme.source`,
`theme.custom_palette`, `theme.mode`, the popup and dock opacities,
`shell.font_family` and the default wallpaper path as a second definition, and
setting one of those through `settings` is a conflict the module system
reports. Change them through Stylix or choose another `theme.source`.

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
`othrys.desktop.lockCommand` signal), screen off (DPMS through the running compositor),
and optional suspend. The stages must increase in that order, and the module
refuses a configuration where a later stage fires first. Conflicts with
Noctalia, which manages idle itself. Noctalia reads the same `timeouts` for
its own lock, screen-off and suspend behaviors, so a Noctalia host locks on
the same schedule without enabling this module; the dim stage has no Noctalia
equivalent.

The module declares the PAM service of each locker it installs, `hyprlock` for
Hyprland and `swaylock` for Niri or an unmanaged compositor, and so does ashell
for its lock button. A
locker whose PAM service is missing rejects the correct password, and the only
way out is a VT switch. On a Noctalia host the lock command falls back to that
locker when the shell is not running.

### Options

```nix
{{#include ../../../modules/desktop/idle.nix:idle-options}}
```

## Night light

Color temperature shifting via gammastep. The schedule needs a location, and
the module refuses to evaluate without one. Provide `latitude` and `longitude`
from the host, or set `geoclue.enable` to have the location resolved.
Conflicts with Noctalia's built-in night light.

`geoclue.enable` is off by default because it turns on `services.geoclue2` for
the whole host. With the nixpkgs defaults geoclue scans for nearby Wi-Fi
networks, sends their hardware addresses to an online location service on
every query, and answers any application that asks for the location. A host
with fixed coordinates needs none of that.

```nix
othrys.desktop.nightLight = {
  enable = true;
  latitude = 40.7;
  longitude = -74.0;
};
```

### Options

```nix
{{#include ../../../modules/desktop/night-light.nix:night-light-options}}
```
