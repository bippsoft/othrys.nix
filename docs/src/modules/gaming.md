# Gaming

Gaming modules under `othrys.apps.gaming.*`. Located in `modules/apps/gui/gaming/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Steam | `othrys.apps.gaming.steam` | Steam with FHS environment, Proton-GE, essential libraries |
| GameMode | `othrys.apps.gaming.gamemode` | Performance optimizer with NVIDIA support |
| MangoHud | `othrys.apps.gaming.mangohud` | Vulkan and OpenGL overlay for FPS, temperatures and CPU/GPU usage |
| PrismLauncher | `othrys.apps.gaming.prismlauncher` | Minecraft launcher with persistent instances |
| osu! | `othrys.apps.gaming.osu` | osu!lazer with low-latency audio, and a pen tablet on by default |
| r2modman | `othrys.apps.gaming.r2modman` | Mod manager for Thunderstore games |

## Steam

- FHS environment with essential X11, audio, and system libraries
- Proton-GE for compatibility
- Three firewall options, each off until a host turns it on
- Gamescope session support
- The ntsync driver, on by default from kernel 6.14

Steam turns on `othrys.hardware.ntsync` at `mkDefault` wherever the kernel
ships the driver. Proton 10 and later use `/dev/ntsync` for Windows
synchronization primitives when they can open it.
[Hardware](./hardware.md#ntsync) describes the driver and the device access.

The module opens no port by default. Each option below opens its ports on
every interface, so a host turns on the ones it uses.

| Option | Opens | For |
|--------|-------|-----|
| `remotePlay.openFirewall` | TCP 27036 and 27037, UDP 10400, 10401 and 27031 to 27036 | streaming a game from this host to another device |
| `localNetworkGameTransfers.openFirewall` | TCP 27040, UDP 27036 | copying an installed game from another Steam client on the network |
| `dedicatedServer.openFirewall` | TCP and UDP 27015 | a Source Dedicated Server |

Remote Play and local transfers still work outward with the ports closed. The
options matter on the host that serves the stream or the game files.

Steam's per-app shader caches persist with the Steam tree, but the DRIVER
shader caches they depend on live in `~/.cache` and NVIDIA's is capped at
1 GiB, so pair Steam with `othrys.hardware.graphics.shaderCache` (see
[Hardware](hardware.md)) or large Vulkan titles recompile shaders every
launch on impermanence hosts.

Steam deletes every game's compiled shader cache when the GPU driver version
changes, so each driver update is followed by one full recompile per game. Two
passes do that work. The background pass drains the queue while Steam is idle,
and only runs once "Allow background processing of Vulkan shaders" is enabled in
Steam under Settings, Downloads. The pre-launch pass covers whatever is left and
blocks the game behind the "Processing Vulkan shaders" dialog. With nothing set,
the pre-launch pass was measured at about 16 pipelines per second on a 32-thread
desktop, where the same replay reaches 223 per second at 28 threads.
`shaderPrecache.backgroundThreads` and `shaderPrecache.highPriorityThreads` pin
the thread count of each pass. Both render into
`~/.local/share/Steam/steam_dev.cfg`, which the client reads as a console script
at start, and `devConfig` writes any other console variable into the same file.

## GameMode

Enables `programs.gamemode` with renice support and writes these defaults into
`gamemode.ini`:

- `renice = 15`
- Screensaver inhibit
- GPU optimisations on device 0, which are NVIDIA PowerMizer performance mode
  (`nv_powermizer_mode = 1`) and `amd_performance_level = "high"`
- Desktop notifications on start and stop

`settings` is merged over those defaults and has the shape of `gamemode.ini`,
a section name over keys whose values are a string, a number, a boolean or a
list of those. Each default is written with `mkDefault`, so setting one key
leaves the others in place.

### What GameMode needs from the host

- **The `gamemode` group.** GameMode sets the CPU governor, the split-lock
  mitigation and the GPU settings through root helpers, and NixOS's polkit
  rule runs them only for members of `gamemode`. The module adds the primary
  user when `othrys.system.users.enable` is on. Another account needs the
  group in its own `extraGroups`, and a session started before the change
  needs a fresh login. Without the group each helper is refused and the
  governor stays where it was.

- **A game that asks for it.** The daemon acts only for a process started
  through `gamemoderun` or a client that requests it. The osu! wrapper on this
  page does so, and a Steam title needs `gamemoderun %command%` in its launch
  options.
- **GPU index 0.** `gpu.gpu_device` defaults to `0`. A host whose gaming GPU
  has another index sets `settings.gpu.gpu_device`.
- **Consent to GPU changes.** The module writes
  `apply_gpu_optimisations = "accept-responsibility"`, the literal value
  GameMode requires before it changes the GPU power state. With it set,
  GameMode switches the PowerMizer mode or the AMD performance level each
  time a game starts, as root and with no password prompt for a member of
  `gamemode`. The NVIDIA switch goes through `nvidia-settings`, which needs an
  X display, so under a Wayland compositor such as niri or Hyprland it does
  nothing. GameMode documents these GPU settings as able to damage hardware,
  which is why the value is spelled as an acceptance. A host that does not
  want that sets `settings.gpu.apply_gpu_optimisations = 0`, which leaves the
  GPU alone and keeps the CPU and scheduling changes.
- **A notification daemon.** The start and end hooks call `notify-send`, and
  the module installs `libnotify` for it. Nothing is shown on a session with
  no notification daemon running.

## MangoHud

The overlay package is installed system-wide, since it loads into the graphics
stack of every Vulkan and OpenGL application, while its configuration goes
through Home Manager. The overlay colours come from `othrys.theme.palette`, and
on a host with no palette the overlay keeps MangoHud's own colours.

`enableSessionWide`, off by default, sets `MANGOHUD=1` for the session so every
Vulkan application shows the overlay. With it off, a game is started through
`mangohud` to show it. `settings` is merged over the module defaults.
`~/.config/MangoHud` and `~/.local/share/MangoHud` are persisted under
impermanence, the second of which holds the logs that `F2` starts and stops.

## osu!

- **Low-latency wrapper**: Injects `PIPEWIRE_LATENCY=64/48000` (1.3ms target) and launches through `gamemoderun`
- **Tablet**: Turns on `othrys.hardware.tablet` at `mkDefault`, which runs
  OpenTabletDriver, as [Hardware](./hardware.md#tablet) describes
- **Persistence**: Auto-persists `~/.local/share/osu` (songs, skins, replays)

## PrismLauncher

Automatically persists `~/.local/share/PrismLauncher` (instances, mods, accounts, settings).
