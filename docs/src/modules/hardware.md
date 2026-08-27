# Hardware

Hardware modules under `othrys.hardware.*`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Audio | `othrys.hardware.audio` | PipeWire audio with persistence |
| NVIDIA | `othrys.hardware.nvidia` | NVIDIA GPU drivers |
| NVIDIA PRIME | `othrys.hardware.nvidia.prime` | Intel + NVIDIA hybrid offload (laptop) |
| Shader cache | `othrys.hardware.graphics.shaderCache` | Persistent, size-tuned GPU shader disk caches |
| Laptop | `othrys.hardware.laptop` | Power management, TLP |
| PowerSpec 1710 | `othrys.hardware.laptop.powerspec-1710` | Laptop-specific hardware quirks |
| Scanner | `othrys.hardware.scanner` | SANE scanning (network discovery via airscan) |
| SMART | `othrys.hardware.smart` | Disk health monitoring (smartd + notify hook) |
| UPS | `othrys.hardware.ups` | UPS monitoring and clean shutdown (NUT) |
| Webcam | `othrys.hardware.webcam` | Webcam support |
| USB | `othrys.hardware.usb` | USB utilities (usbutils) |
| Bluetooth | `othrys.hardware.wireless.bluetooth` | Bluetooth with persistence |
| WiFi | `othrys.hardware.wireless.wifi` | WiFi via NetworkManager |

## NVIDIA (Dedicated)

```nix
{{#include ../../../modules/hardware/graphics/nvidia.nix:nvidia-config}}
```

Key features:

- Modesetting enabled (required for Wayland)
- Open kernel modules for RTX 20+ series
- VA-API and VDPAU drivers for hardware video decode
- 32-bit support for Steam/gaming
- Kernel modules loaded in initrd to claim DRM device early
- Blacklists `i915` and `nouveau` to prevent conflicts

## NVIDIA PRIME (Hybrid Offload)

For laptops with Intel iGPU + NVIDIA dGPU. Uses PRIME offload, so Intel handles display and NVIDIA is available on demand.

### Options

```nix
{{#include ../../../modules/hardware/graphics/prime.nix:prime-options}}
```

## Shader Cache

Driver-level shader disk caches (`~/.cache/nvidia`, `~/.cache/mesa_shader_cache*`)
are wiped by impermanence and, on NVIDIA, evicted past a 1 GiB default cap,
which together undo Steam's shader pre-caching and force per-launch recompiles
in large Vulkan titles. This module persists the cache directories and raises
the NVIDIA cap session-wide. Steam's own per-app caches live inside the
persisted Steam tree already (see [Gaming](gaming.md)).

### Options

```nix
{{#include ../../../modules/hardware/graphics/shader-cache.nix:shader-cache-options}}
```

## Scanner

SANE with network-scanner discovery (sane-airscan covers most modern
eSCL/WSD devices), and vendor drivers go in `extraBackends`. The `simple-scan`
GUI follows the graphical signal, and headless scan servers use `scanimage`.

### Options

```nix
{{#include ../../../modules/hardware/scanner.nix:scanner-options}}
```

## SMART

Disk health monitoring via smartd over auto-detected devices. Warnings hit
the wall by default. With `othrys.services.notify` enabled they are also
pushed through `othrys-notify`.

### Options

```nix
{{#include ../../../modules/hardware/smart.nix:smart-options}}
```

## UPS

NUT in standalone mode: the attached UPS is monitored, low battery triggers
a clean shutdown, and power events push through `othrys-notify` when the
notify module is enabled. The monitor password is a secrets-provider path.

### Options

```nix
{{#include ../../../modules/hardware/ups.nix:ups-options}}
```
