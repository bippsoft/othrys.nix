# Gaming

Gaming modules under `othrys.apps.gaming.*`. Located in `modules/apps/gui/gaming/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Steam | `othrys.apps.gaming.steam` | Steam with FHS environment, Proton-GE, essential libraries |
| GameMode | `othrys.apps.gaming.gamemode` | Performance optimizer with NVIDIA support |
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

Performance optimization with per-application settings:

- Soft realtime scheduling
- Screensaver inhibit
- NVIDIA PowerMizer performance mode (`nv_powermizer_mode = 1`)
- Desktop notifications on start/stop

## osu!

- **Low-latency wrapper**: Injects `PIPEWIRE_LATENCY=64/48000` (1.3ms target) and launches with GameMode
- **Tablet driver**: Enables `hardware.opentabletdriver` daemon
- **Persistence**: Auto-persists `~/.local/share/osu` (songs, skins, replays)

### Tablet Setup

1. Run `opentabletdriver` from application menu
1. Configure tablet area, bindings, and preferences
1. Settings save to `~/.config/OpenTabletDriver/settings.json`

**Important**: In-game, ensure "High Precision Mouse/Tablet" is **DISABLED** so the system driver handles input.

## PrismLauncher

Automatically persists `~/.local/share/PrismLauncher` (instances, mods, accounts, settings).
