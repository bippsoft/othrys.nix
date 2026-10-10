# Gaming

Gaming modules under `othrys.apps.gaming.*`. Located in `modules/apps/gui/gaming/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Steam | `othrys.apps.gaming.steam` | Steam with FHS environment, Proton-GE, essential libraries |
| GameMode | `othrys.apps.gaming.gamemode` | Performance optimizer with NVIDIA support |
| MangoHud | `othrys.apps.gaming.mangohud` | Vulkan and OpenGL overlay for FPS, temperatures and CPU/GPU usage |
| PrismLauncher | `othrys.apps.gaming.prismlauncher` | Minecraft launcher with persistent instances |
| osu! | `othrys.apps.gaming.osu` | osu!lazer with OpenTabletDriver and low-latency audio |
| r2modman | `othrys.apps.gaming.r2modman` | Mod manager for Thunderstore games |

## Steam

- FHS environment with essential X11, audio, and system libraries
- Proton-GE for compatibility
- Firewall rules for Remote Play and LAN transfers, with the dedicated server ports opt-in
  (`dedicatedServer.openFirewall`, which opens TCP and UDP 27015 and defaults to `false`)
- Gamescope session support

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

- Soft realtime scheduling (`softrealtime = "auto"`) and `renice = 15`
- Screensaver inhibit
- GPU optimisations on device 0, which are NVIDIA PowerMizer performance mode
  (`nv_powermizer_mode = 1`) and `amd_performance_level = "high"`
- Desktop notifications on start and stop

`settings` is merged over those defaults and has the shape of `gamemode.ini`,
a section name over keys whose values are a string, a number, a boolean or a
list of those. Each default is written with `mkDefault`, so setting one key
leaves the others in place.

### What GameMode needs from the host

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
  time a game starts. A host that does not want that sets
  `settings.gpu.apply_gpu_optimisations = 0`.
- **A notification daemon.** The start and end hooks call `notify-send`, and
  the module installs `libnotify` for it. Nothing is shown on a session with
  no notification daemon running.

## MangoHud

The overlay package is installed system-wide, since it loads into the graphics
stack of every Vulkan and OpenGL application, while its configuration goes
through Home Manager. The module requires `othrys.system.stylix.enable`,
because the overlay colours are read from the Stylix palette, and it fails an
assertion naming that option without it.

`enableSessionWide`, off by default, sets `MANGOHUD=1` for the session so every
Vulkan application shows the overlay. With it off, a game is started through
`mangohud` to show it. `settings` is merged over the module defaults.
`~/.config/MangoHud` and `~/.local/share/MangoHud` are persisted under
impermanence, the second of which holds the logs that `F2` starts and stops.

## osu!

- **Low-latency wrapper**: Injects `PIPEWIRE_LATENCY=64/48000` (1.3ms target) and launches through `gamemoderun`
- **Tablet driver**: Enables `hardware.opentabletdriver` daemon
- **Persistence**: Auto-persists `~/.local/share/osu` (songs, skins, replays) and `~/.config/OpenTabletDriver`

### Tablet Setup

1. Run `opentabletdriver` from application menu
1. Configure tablet area, bindings, and preferences
1. Settings save to `~/.config/OpenTabletDriver/settings.json`

**Important**: In-game, ensure "High Precision Mouse/Tablet" is **DISABLED** so the system driver handles input.

## PrismLauncher

Automatically persists `~/.local/share/PrismLauncher` (instances, mods, accounts, settings).
