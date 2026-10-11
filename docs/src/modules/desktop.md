# Desktop

Desktop environment modules under `othrys.desktop.*`. Handles compositors, status bar, and session management.

Colours and fonts come from `othrys.theme`, see [Theming](../guides/theming.md).

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Ashell | `othrys.desktop.ashell` | GPU-accelerated status bar, coloured from `othrys.theme` |
| Hyprland | `othrys.desktop.compositors.hyprland` | Wayland compositor (dynamic tiling) |
| Niri | `othrys.desktop.compositors.niri` | Wayland compositor (scrollable tiling) |
| Idle | `othrys.desktop.idle` | Staged idle management (dim, lock, screen off, suspend) |
| Keyring | `othrys.desktop.keyring` | Secret Service provider (gnome-keyring), on by default on a graphical host |
| Login | `othrys.desktop.login` | greetd login manager (tuigreet or cosmic-greeter) |
| Night light | `othrys.desktop.nightLight` | Color temperature shifting (gammastep) |
| UWSM | `othrys.desktop.uwsm` | Systemd session management for Wayland |

## Ashell

Status bar for Hyprland or Niri. Either compositor satisfies its assertion, and the lock and logout commands follow the session that is running, as described under [Sessions](#sessions). Installed from the `ashell` flake input, configured via a generated `~/.config/ashell/config.toml` with the colours of `othrys.theme.palette` and the font of `othrys.theme.fonts.sansSerif` written in at build time. A null palette or font leaves the matching keys out, and ashell uses its own defaults. Hot-reloads on config changes.

The module installs wofi as the launcher, rofimoji as the emoji picker, the
locker of each enabled compositor and, on Hyprland, hyprpicker. The audio
buttons open pavucontrol, which `othrys.hardware.audio` installs on a graphical
host.

The clock shows no weather until `weatherLocation` is set. With the default of
`null` the key is left out of the config and the bar makes no forecast request.
The value is a city name or a pair of coordinates, and it is identity-shaped, so
the host sets it. The module renders either form as the `weather_location`
table ashell reads. A string holding a brace or an equals sign is refused,
which catches the raw TOML fragment the option used to take.

```nix
othrys.desktop.ashell.weatherLocation = {
  latitude = 40.7128;
  longitude = -74.006;
};

othrys.desktop.ashell.weatherLocation = "New York";
```

The clipboard button reads a history that cliphist keeps, fed by a Home Manager
user service on Hyprland and on Niri alike. The history is a plain file under
`~/.cache/cliphist` and holds everything copied, apart from entries a password
manager marks as sensitive. It keeps `clipboard.maxItems` entries, 100 by
default, and the default lock command wipes it each time the session locks. A
host that replaces `othrys.desktop.lockCommand` takes over that wipe. A second
user unit, `cliphist-wipe`, wipes the history when the graphical session ends,
at logout, reboot or shutdown, whatever the lock command is. A session that
dies without stopping its units, as on a power cut, leaves the file in place
until the next lock or logout.
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
host where niri is the only compositor. The window border takes the accent
of `othrys.theme.palette` in place of niri's focus ring. On a host with the
Stylix adapter, niri-flake's Stylix target themes the cursor as well.

`outputs` takes JSON values only, which is everything an output is made of.
`extraBinds` and `settings` stay free-form, since an action written with
niri-flake's `config.lib.niri.actions` helpers is an attribute set carrying a
function, and niri-flake validates both once they reach
`programs.niri.settings`.

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

## Idle

Staged idle policy via hypridle (ext-idle-notify, which works on Hyprland and
Niri): optional backlight dim, lock (via the shared
`othrys.desktop.lockCommand` signal), screen off (DPMS through the running compositor),
and optional suspend. The stages must increase in that order, and the module
refuses a configuration where a later stage fires first.

`lockBeforeSleep`, on by default, locks the session before the host sleeps.
With the module enabled it is hypridle's before-sleep command. A Hyprland or
Niri host that does not enable this module still gets hypridle for that one
job, configured with the lock command and no idle stage, together with the
locker and its PAM service. Such a host therefore locks on suspend and on
`loginctl lock-session` and never on idle time. Setting
`othrys.desktop.idle.lockBeforeSleep = false` removes the before-sleep lock in
both cases.

The module declares the PAM service of each locker it installs, `hyprlock` for
Hyprland and `swaylock` for Niri or an unmanaged compositor, and so does ashell
for its lock button. A
locker whose PAM service is missing rejects the correct password, and the only
way out is a VT switch.

### Options

```nix
{{#include ../../../modules/desktop/idle.nix:idle-options}}
```

## Keyring

Browsers, mail clients and tray applications store credentials in the Secret
Service, and a session without a provider leaves each of them to fall back to a
plain file or to ask again on every start. `othrys.desktop.keyring.enable` runs
gnome-keyring as that provider. Its default is `othrys.desktop.graphical`, so a
Hyprland host, a niri host and a host with an unmanaged desktop all get one,
while a headless host does not.

With `othrys.desktop.login` the greeter passes the login password to the
keyring, which is unlocked when the session starts. This holds while the
keyring password and the login password are the same. An autologin session has
no password to pass, so the keyring asks for its own the first time an
application reads a secret. Under impermanence `~/.local/share/keyrings` is
persisted at mode 0700 for the primary user.

A host that runs another provider, such as KeePassXC or KWallet, turns the
option off, since two providers compete for the same D-Bus name. niri-flake
enables gnome-keyring on every niri host by itself, and the option overrides
that when it is off.

```nix
othrys.desktop.keyring.enable = false;
```

### Options

```nix
{{#include ../../../modules/desktop/keyring.nix:keyring-options}}
```

## Night light

Color temperature shifting via gammastep. The schedule needs a location, and
the module refuses to evaluate without one. Provide `latitude` and `longitude`
from the host, or set `geoclue.enable` to have the location resolved.

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
