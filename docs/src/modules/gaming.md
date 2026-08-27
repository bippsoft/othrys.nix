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
- Firewall rules for Remote Play, dedicated server, and LAN transfers
- Gamescope session support

Steam's per-app shader caches persist with the Steam tree, but the DRIVER
shader caches they depend on live in `~/.cache` and NVIDIA's is capped at
1 GiB, so pair Steam with `othrys.hardware.graphics.shaderCache` (see
[Hardware](hardware.md)) or large Vulkan titles recompile shaders every
launch on impermanence hosts.

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
