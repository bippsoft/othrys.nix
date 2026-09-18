# System

Core system modules under `othrys.system.*`, located in `modules/system/`. Each
is toggled by its own `enable` option (except `user`, which only declares the
identity option) and configures a fundamental part of the machine.

The disk, impermanence, bootloader, and secrets modules have dedicated pages
under **System Infrastructure**, and the rest are summarized here.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| User identity | `othrys.system.user.name` | Primary user account name, **required**, replaces the legacy `username` specialArg |
| Users | `othrys.system.users` | User account creation, shell, password wiring |
| Locale | `othrys.system.locale` | Timezone, locale, console font/keymap (defaults are identity-neutral: `UTC`) |
| Auto-upgrade | `othrys.system.autoUpgrade` | Unattended nixos-rebuild from the fleet flake |
| Nix | `othrys.system.nix` | Nix settings, GC/`nh`, substituters, optional Cachix |
| Kernel | `othrys.system.kernel` | Kernel package selection (disabled → NixOS default kernel) |
| Hardening | `othrys.system.hardening` | Opt-in kernel and sysctl hardening profile, with the costly switches kept separate |
| Networking | `othrys.system.networking` | systemd-networkd: per-interface DHCP/static + bridges/VLANs (router topology) |
| Git | `othrys.system.git` | Git identity and aliases (home-manager) |
| Persistence | `othrys.system.persistence` | System/user state declarations for impermanence |
| Stylix | `othrys.system.stylix` | System-wide base16 theming (fonts/cursor/opacity) |
| Shell | `othrys.system.shell.{bash,zsh,starship}` | Interactive shells and prompt |

## Notes

- **User identity**: modules read `config.othrys.system.user.name`. It is a
  required option with no default and no `username` specialArg fallback, so set it
  per host. See the consumer contract in the repository `CLAUDE.md`.
- **State version**: `othrys.system.nix.stateVersion` is likewise required with
  no default. It records the release a host was first installed at, so the
  library cannot supply one on the host's behalf.
- **Identity-neutral defaults**: `locale.timezone` defaults to `UTC` and
  `nix.nh.flake` defaults to `null`; set them per host. These are examples of
  the library's "sane, non-personal defaults" policy.

## Auto-upgrade

Unattended `nixos-rebuild` from the fleet flake on a schedule (daily 04:00
by default, randomized delay so a fleet doesn't stampede the repo host).
Reboots are opt-in and window-confined, and failures push through
`othrys-notify` when the notify module is enabled.

### Options

```nix
{{#include ../../../modules/system/auto-upgrade.nix:auto-upgrade-options}}
```

## Hardening

`othrys.system.hardening` is an opt-in profile. With `enable` off, which is the
default, the module sets nothing. With it on, the host gets the sysctls below,
which cost nothing on an ordinary workstation or server.

| sysctl | Value | Effect |
|--------|-------|--------|
| `kernel.kptr_restrict` | `2` | Kernel pointers are hidden from every user, root included |
| `kernel.dmesg_restrict` | `1` | Reading the kernel log needs `CAP_SYSLOG` |
| `kernel.unprivileged_bpf_disabled` | `1` | Only privileged processes load BPF programs |
| `net.core.bpf_jit_harden` | `2` | The BPF JIT blinds constants for all users |
| `kernel.yama.ptrace_scope` | `1` | A process attaches only to its own descendants |
| `kernel.kexec_load_disabled` | `1` | No new kernel can be loaded with kexec until reboot |
| `net.ipv4.conf.{all,default}.rp_filter` | `2` | Loose reverse path filtering |
| `net.ipv4.conf.{all,default}.accept_redirects` | `0` | ICMP redirects are ignored |
| `net.ipv4.conf.{all,default}.secure_redirects` | `0` | Redirects from listed gateways are ignored as well |
| `net.ipv4.conf.{all,default}.send_redirects` | `0` | The host sends no ICMP redirects |
| `net.ipv6.conf.{all,default}.accept_redirects` | `0` | IPv6 redirects are ignored |
| `net.ipv4.conf.{all,default}.accept_source_route` | `0` | Source-routed IPv4 packets are dropped |
| `net.ipv6.conf.{all,default}.accept_source_route` | `0` | Source-routed IPv6 packets are dropped |
| `net.ipv4.tcp_syncookies` | `1` | SYN cookies are used when the SYN queue overflows |
| `net.ipv4.icmp_echo_ignore_broadcasts` | `1` | Broadcast pings are ignored |
| `net.ipv4.tcp_rfc1337` | `1` | A reset does not end a connection in TIME-WAIT |

### Reverse path filtering

`rp_filter` is loose (2) rather than strict (1). Strict mode drops a packet when
the route back to its sender leaves through a different interface, which is the
normal state of a Tailscale exit node client and of a multi-homed router. The
kernel applies this check regardless of the firewall, so a strict sysctl would
also undo the loose `networking.firewall.checkReversePath` that NixOS selects
when `othrys.services.tailscale` is on. Loose mode still drops packets whose
source is unreachable through any interface.

`othrys.services.router` assigns strict mode on its own, and that assignment
wins over the profile, so a router with the profile on keeps strict filtering.

### Overriding one value

Every sysctl is written at priority 900. That is above the `mkDefault`
definitions NixOS ships for `kernel.kptr_restrict` and, under
`security.protectKernelImage`, for `kernel.kexec_load_disabled`. It is below a
plain assignment, so a host changes one value by assigning it, with no
`mkForce`.

```nix
{
  othrys.system.hardening.enable = true;

  # A debugger has to attach to processes it did not start.
  boot.kernel.sysctl."kernel.yama.ptrace_scope" = 0;
}
```

### The costly switches

Two further options stay off unless the host asks for them, because each one
breaks something.

- `lockKernelModules` sets `security.lockKernelModules`. No module loads after
  boot, so hardware plugged in later, and VPN or filesystem modules that were
  not loaded at boot, stop working until the next reboot. List the modules the
  host needs later in `boot.kernelModules`.
- `protectKernelImage` sets `security.protectKernelImage`. Hibernation and kexec
  are disabled. Evaluation fails when the host sets `boot.resumeDevice` or
  passes `resume=` in `boot.kernelParams`.

The profile has no switch for unprivileged user namespaces. nixpkgs removed
`security.unprivilegedUsernsClone` together with the hardened kernels that
carried the sysctl. The remaining upstream switch, `security.allowUserNamespaces`,
turns user namespaces off for every user and conflicts with the Nix build
sandbox, so a host that wants it sets it directly.

### Options

```nix
{{#include ../../../modules/system/hardening.nix:hardening-options}}
```
