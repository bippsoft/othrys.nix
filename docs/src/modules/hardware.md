# Hardware

Hardware modules under `othrys.hardware.*`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Audio | `othrys.hardware.audio` | PipeWire audio with persistence |
| CPU | `othrys.hardware.cpu` | Microcode, firmware and KVM for the processor's vendor |
| NVIDIA | `othrys.hardware.nvidia` | NVIDIA GPU drivers |
| NVIDIA PRIME | `othrys.hardware.nvidia.prime` | Intel + NVIDIA hybrid offload (laptop) |
| Shader cache | `othrys.hardware.graphics.shaderCache` | Persistent, size-tuned GPU shader disk caches |
| Laptop | `othrys.hardware.laptop` | Power management, TLP |
| PowerSpec 1710 | `othrys.hardware.laptop.powerspec-1710` | Laptop-specific hardware quirks |
| Scanner | `othrys.hardware.scanner` | SANE scanning (network discovery via airscan) |
| SMART | `othrys.hardware.smart` | Disk health monitoring (smartd + notify hook) |
| UPS | `othrys.hardware.ups` | UPS monitoring and clean shutdown (NUT) |
| Webcam | `othrys.hardware.webcam` | V4L2 utilities (`v4l-utils`) |
| USB | `othrys.hardware.usb` | USB utilities (usbutils) |
| Bluetooth | `othrys.hardware.wireless.bluetooth` | Bluetooth, with `/var/lib/bluetooth` persisted at 0700 since it holds the link keys |
| WiFi | `othrys.hardware.wireless.wifi` | WiFi via NetworkManager, persisting `system-connections` and `/var/lib/NetworkManager` only |

## Audio

PipeWire with its ALSA, PulseAudio and JACK front ends, and rtkit for real-time
scheduling. Two options change what PipeWire does out of the box.

`lowLatency`, on by default, sets the graph quantum to 512 frames. PipeWire
ships 1024, which is 21.3 ms of buffering per cycle at 48 kHz, and 512 halves
that to 10.7 ms. The sample rate and the quantum bounds stay at the PipeWire
values, so a client that asks for a smaller buffer still gets one.

`usbDuplexProfile`, off by default, pins every USB audio device to the
`output:analog-stereo+input:mono-fallback` profile. It suits a headset that
WirePlumber brings up output-only. A device without that profile, such as a
multichannel interface, ends up with no profile at all and stays silent, which
is why a host has to ask for it.

## CPU

`othrys.hardware.cpu.vendor` names the processor's vendor, `"intel"` or `"amd"`,
on a host that runs on its own hardware. With it set, the module turns on that
vendor's microcode updates, `hardware.enableRedistributableFirmware` and the
vendor's KVM module.

```nix
othrys.hardware.cpu.vendor = "amd";
```

`nixos-generate-config` writes the same three settings into `hardware.nix`. A
host installed another way, as with disko, has no such file, and NixOS defaults
all three to off, so the host runs whatever microcode its board shipped. The
default is `null`, which writes nothing and suits a virtual machine, since the
hypervisor owns the microcode there. The firmware setting is written at
`mkDefault`, so a host can keep the microcode and leave the firmware off.
`othrys.hardware.laptop.powerspec-1710` sets the vendor to `"intel"`.

### Options

```nix
{{#include ../../../modules/hardware/cpu.nix:cpu-options}}
```

## NVIDIA (Dedicated)

```nix
{{#include ../../../modules/hardware/graphics/nvidia.nix:nvidia-config}}
```

Key features:

- Modesetting enabled (required for Wayland)
- Open kernel modules by default, which suit Turing and newer (GTX 16, RTX 20 onward)
- The driver is an option, `package`, defaulting to the stable branch
- VA-API and VDPAU drivers for hardware video decode
- 32-bit support for Steam/gaming
- Kernel modules loaded in the initrd on a host without PRIME, which `earlyLoad` decides
- Blacklists `nouveau`, and `i915` as well when `blacklistIntel` is set

`blacklistIntel` is off by default. On a desktop whose CPU has an iGPU, the
Intel driver is harmless beside the NVIDIA one, and blacklisting it takes away
the motherboard outputs and Quick Sync. Set it on a host where the iGPU must
never bind. PRIME renders the display on the iGPU, so `blacklistIntel` together
with `prime.enable` fails evaluation.

`earlyLoad` decides whether the four NVIDIA kernel modules go into the initrd.
With it on, the NVIDIA card can draw the disk-unlock prompt and the boot splash,
and every initrd carries the driver and its firmware. With it off, the modules
are listed in `boot.kernelModules` and loaded from the root filesystem once it
is mounted. The default is on for a desktop and off with `prime.enable`, since
the Intel GPU drives a PRIME laptop's panel during boot and `i915` stays in the
initrd either way. On a PRIME host with the 580 legacy driver the initrd
measures 207M with early loading and 50M without. With a 1G boot partition and
a 12M kernel that is four generations against sixteen.

### Older cards

The stable driver and the open kernel modules both leave older cards behind, and
nothing at evaluation can tell which card a host has. With either one wrong, the
kernel module never binds to the card. The symptom is
`NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver`,
and `sudo dmesg | grep -i nvrm` names the branch the card needs.

| Card generation | `openModules` | `package` |
|-----------------|---------------|-----------|
| Turing and newer (GTX 16, RTX 20 onward) | `true`, the default | the default |
| Maxwell, Pascal, Volta (GTX 900, GTX 10, Titan V) | `false` | `nvidiaPackages.legacy_580` |
| Kepler (GTX 600 and 700) | `false` | `nvidiaPackages.legacy_470` |

```nix
{config, ...}: {
  othrys.hardware.nvidia = {
    enable = true;
    openModules = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  };
}
```

Take the package from `config.boot.kernelPackages`, so its kernel modules are
built for the kernel the host runs. A switch does not replace a kernel module
that is already loaded, so reboot after changing either option.

## NVIDIA PRIME (Hybrid Offload)

For laptops with Intel iGPU + NVIDIA dGPU. Uses PRIME offload, so Intel handles display and NVIDIA is available on demand.

`intelBusId` and `nvidiaBusId` have no default and PRIME fails evaluation until
both are set. The addresses differ between boards, and a wrong pair boots to a
black screen with nothing in the evaluation to point at it. `lspci` prints
them in hexadecimal as `bus:device.function` and the options take decimal, so
`01:00.0` becomes `PCI:1:0:0` and `0a:00.0` becomes `PCI:10:0:0`.

```nix
othrys.hardware.nvidia = {
  enable = true;
  prime = {
    enable = true;
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
};
```

`prime.enable` on a host without `othrys.hardware.nvidia.enable` also fails
evaluation, since PRIME configures nothing without the driver.

The module sets no kernel parameter. nixpkgs turns `nvidia-drm.modeset` on for
an offload host and sets `NVreg_PreserveVideoMemoryAllocations` together with
the suspend services whenever `hardware.nvidia.powerManagement.enable` is on,
which it is by default with PRIME. A host that turns power management off
therefore loses the parameter and the services together.

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

Discovery runs over mDNS, so the module turns on `services.avahi` with
`nssmdns4`, both at `mkDefault`. A host that sets `services.avahi.enable = false` keeps the scanners it names by hand in `airscan.conf` and finds no
others.

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

upsmon runs its notify command as the unprivileged `nutmon` user, which cannot
read a root-only `othrys.services.notify.tokenFile`. The module loads the token
into `upsmon.service` as a systemd credential and copies it before start to
`/run/nut/othrys-notify/token`, owned by that user, so the token file itself
keeps its `root:0400` ownership and the event still arrives authenticated.

### Options

```nix
{{#include ../../../modules/hardware/ups.nix:ups-options}}
```

## Webcam

Installs `v4l-utils` and adds no group. logind gives the user at the seat
access to camera nodes through a udev ACL. The `video` group is not needed for
that, and membership would open the DRM, framebuffer and backlight nodes to the
user from every session, an SSH login included.

## Bluetooth

BlueZ with pairings persisted under `/var/lib/bluetooth` and the Blueman applet
on graphical hosts. A2DP needs no key in `main.conf`, since PipeWire registers
the audio endpoints with BlueZ when `othrys.hardware.audio` is on.
`experimental` turns on the BlueZ experimental interfaces, which battery
reporting uses.

The persisted directory is mode `0700`. The tree holds the link keys of every
paired device under a directory per adapter, and `bluetoothd` creates it
`0700` itself, so it keeps the mode the daemon would have chosen.

## WiFi

NetworkManager, with declarative networks under `networks` and their
passphrases read from `environmentFile`. The variable for a network is
`WIFI_PSK_` followed by its key under `networks` in upper case, with every
character other than a letter, a digit or an underscore replaced by an
underscore. The key `guest-5g.lan` reads `WIFI_PSK_GUEST_5G_LAN`. Two keys that
map to one variable fail evaluation.

NetworkManager persists `/etc/NetworkManager/system-connections`, which holds
the saved connections and their secrets, and `/var/lib/NetworkManager`, which
holds the leases, the seen BSSIDs and the timestamps autoconnect ranks by.
`/etc/NetworkManager` itself is left on the ephemeral root. NixOS writes
`NetworkManager.conf` and the `conf.d` fragments there as store symlinks at
activation, and a bind mount over the whole directory would hide every one of
them, so the daemon would start with its stock defaults and none of the
settings the host declares.

