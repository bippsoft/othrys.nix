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
| Keyring | `othrys.desktop.keyring` | Secret Service provider (gnome-keyring or `pass`), on by default on a graphical host |
| Login | `othrys.desktop.login` | greetd login manager (tuigreet or cosmic-greeter) |
| Night light | `othrys.desktop.nightLight` | Color temperature shifting (gammastep) |
| UWSM | `othrys.desktop.uwsm` | Systemd session management for Wayland |
| Wallpaper | `othrys.desktop.wallpaper` | Draws `othrys.theme.wallpaper` with wpaperd, on by default where a compositor runs and a wallpaper is declared |

## Ashell

Status bar for Hyprland or Niri. Either compositor satisfies its assertion, and the lock and logout commands follow the session that is running, as described under [Sessions](#sessions). Installed from the ashell flake this library locks, or from `othrys.desktop.ashell.package` when a host sets it, and configured via a generated `~/.config/ashell/config.toml` with the colours of `othrys.theme.palette` and the font of `othrys.theme.fonts.sansSerif` written in at build time. A null palette or font leaves the matching keys out, and ashell uses its own defaults. Hot-reloads on config changes.

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
one provider, which `othrys.desktop.keyring.provider` selects. Its default is
`othrys.desktop.graphical`, so a Hyprland host, a niri host and a host with an
unmanaged desktop all get one, while a headless host does not.

A host that runs another provider, such as KeePassXC or KWallet, turns the
option off, since two providers compete for the same D-Bus name. niri-flake
enables gnome-keyring on every niri host by itself, and the module overrides
that whenever gnome-keyring is not the provider it was asked for.

```nix
othrys.desktop.keyring.enable = false;
```

### gnome-keyring

The default provider encrypts its store with a password. With
`othrys.desktop.login` the greeter passes the login password to the keyring,
which is unlocked when the session starts. This holds while the keyring
password and the login password are the same. Under impermanence
`~/.local/share/keyrings` is persisted at mode 0700 for the primary user.

A login that passes no password leaves the store locked, and the keyring then
asks for its own the first time an application reads a secret. An autologin
session is one such login. A login with a hardware key alone is another, since
a U2F touch yields a signature and no secret, and a signature cannot unlock
anything. The two settings below are the ways out.

### A store without a password

`othrys.desktop.keyring.passwordless` creates the gnome-keyring store with no
password, so nothing ever asks. gnome-keyring has no setting for this. The
module writes the keyring file before the daemon first runs, at Home Manager
activation, and only when neither `login.keyring` nor `Default_keyring.keyring`
exists. A keyring that already exists is never replaced, so a host that had one
with a password keeps it until its owner removes the file.

```nix
othrys.desktop.keyring.passwordless = true;
```

The store is then plain files under `~/.local/share/keyrings`. File permissions
keep other accounts out, and disk encryption keeps out whoever holds the
powered-off machine. Any program running as the user reads every secret, and so
does anyone who reaches the mounted disk, which includes a backup of the home
directory. The greeter is no longer told to unlock the keyring, since there is
nothing to unlock.

The module refuses the option on a host that declares no LUKS device in
`boot.initrd.luks.devices`, which `othrys.system.disko` fills in and a host
that set LUKS up by hand fills in as well. A host that accepts plain secrets on
a plain disk sets `othrys.desktop.keyring.allowUnencryptedDisk`.

### pass

`provider = "pass"` runs `pass-secret-service` for the primary user. It serves
the same D-Bus API from a `pass` password store, where each secret is a file
encrypted to the OpenPGP key named in `othrys.desktop.keyring.pass.gpgKey`.
gnome-keyring is turned off, on a niri host as well.

```nix
othrys.desktop.keyring = {
  provider = "pass";
  pass.gpgKey = "<fingerprint>";
};
```

With the key on a hardware token, reading a secret needs the token, its PIN
once for each gpg-agent session, and a touch on each read when the token's
touch policy for decryption is set to always. A copy of the disk or of a backup
holds ciphertext only. A program running as the user can still ask the service
for a secret while the token is present and the PIN is cached, and the touch
policy is what stands between that program and the secret. The label of an
entry and the attributes applications search by are stored beside it
unencrypted, so the store shows which services have a secret.

The store lives in `~/.local/share/password-store` unless
`othrys.desktop.keyring.pass.directory` says otherwise, and it is persisted at
mode 0700 under impermanence. A new store is initialised by writing its
`.gpg-id` file, and a store that already has one is left as it is. The module
does not import the public key or configure gpg-agent.
`othrys.services.security.yubikey` provides the agent and a pinentry. Home
Manager has to manage the primary user, and the module refuses the provider
without it and without a key.

### Which to pick

| Login | Setting | What unlocks the secrets |
|-------|---------|--------------------------|
| A password, typed at the greeter | The defaults | The login password, passed on by the greeter |
| A hardware key alone, on an encrypted disk | `passwordless = true` | Nothing, since the store has no password and the disk encryption protects it at rest |
| A hardware key alone, with secrets bound to the token | `provider = "pass"` | The OpenPGP key on the token, with its PIN and its touch policy |

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

## Wallpaper

`othrys.theme.wallpaper` says what the wallpaper is, and this module draws it.
It runs [wpaperd](https://github.com/danyspin97/wpaperd) as a user service of
the graphical session and renders the daemon's configuration from the theme.
The same daemon serves Hyprland and niri, so a host draws the same wallpaper
under either. The forms `source` takes, rotation and per-monitor settings are
described in the [theming guide](../guides/theming.md#wallpapers).

`othrys.desktop.wallpaper.enable` is on by default when three things hold. The
host is graphical, an othrys compositor module is enabled, and a wallpaper is
declared, either in `othrys.theme.wallpaper.source` or for a monitor in
`othrys.theme.wallpaper.outputs`. A host with no wallpaper therefore runs no
daemon. Turning the option on by hand with no wallpaper declared fails an
assertion, since the daemon would have nothing to draw.

The unit is wanted by `graphical-session.target` and stops with it. A host that
draws its wallpaper with another program turns the option off, and a host that
used to enable `services.wpaperd` for the primary user itself drops that
setting, since both would write the same configuration file.

```nix
othrys.desktop.wallpaper.enable = false;
```

On a host with the Stylix export, Stylix would start hyprpaper under Hyprland
and write a wpaperd section of its own. The adapter switches those targets off
while this module is on, so one program draws.

### Options

```nix
{{#include ../../../modules/desktop/wallpaper.nix:wallpaper-options}}
```
