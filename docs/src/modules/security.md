# Security

Security modules under `othrys.services.security.*`. Located in `modules/services/security/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Sudo | `othrys.services.security.sudo` | Sudo configuration |
| Polkit | `othrys.services.security.polkit` | PolicyKit rules |
| YubiKey | `othrys.services.security.yubikey` | U2F PAM, GPG agent, SSH keygrips |
| fail2ban | `othrys.services.security.fail2ban` | Intrusion prevention |
| CrowdSec | `othrys.services.security.crowdsec` | CrowdSec engine + nftables firewall bouncer |

## YubiKey

- **U2F PAM**: Physical key required for `sudo` and login
- **GPG agent**: YubiKey-backed GPG with SSH support
- **SSH keygrips**: Specific GPG keygrips for SSH authentication
- **age-plugin-yubikey**: For manual sops secret editing

### Options

```nix
{{#include ../../../modules/services/security/yubikey.nix:yubikey-options}}
```

### Onboarding & Key Rotation

```bash
# New key generation
just yubikey-onboard

# Rotate onto a replacement YubiKey from existing backup
just yubikey-onboard -- --from-backup /mnt/usb/yubikey-backup

# Verify current YubiKey health
just yubikey-onboard -- --verify
```

The onboarding script handles new key generation, key rotation from backup, multi-key redundancy, and outputs all values needed for the NixOS configuration. See the [YubiKey Onboarding guide](../guides/yubikey-onboard.md) for full details.

## fail2ban

Basic intrusion prevention with default jails.

### Options

```nix
{{#include ../../../modules/services/security/fail2ban.nix:fail2ban-options}}
```

## CrowdSec

[CrowdSec](https://www.crowdsec.net/) security engine plus its nftables firewall
bouncer (both from nixpkgs, with no extra flake input). The engine parses logs and
decides, while the bouncer enforces those decisions in nftables. `registerBouncer`
wires the two automatically, so no manual `cscli bouncers add` is required. A
complement to fail2ban: fail2ban bans locally, CrowdSec adds crowd-sourced
blocklists.

Central-console enrollment (to pull community blocklists) is a one-time runtime
step, `cscli console enroll <key>` with a key from your secrets provider, left
to the fleet. Advanced engine/bouncer configuration is available through the
upstream `services.crowdsec.*` / `services.crowdsec-firewall-bouncer.*` options.

The engine runs its own Local API on loopback (`127.0.0.1:8080`), which is what
the agent authenticates against and what the bouncer reads decisions from,
machine credentials are minted on first start under
`/var/lib/crowdsec/state/`. Enable `openFirewall` only if a remote bouncer or a
second engine has to reach that API.

### Options

```nix
{{#include ../../../modules/services/security/crowdsec.nix:crowdsec-options}}
```

### Usage

```nix
othrys.services.security.crowdsec = {
  enable = true;
  collections = ["crowdsecurity/linux" "crowdsecurity/sshd"];   # default
  firewallBouncer.enable = true;                                 # default
};
```

### Upstream workarounds

nixpkgs' `services.crowdsec` cannot start on a host with no pre-existing
`/var/lib/crowdsec`. The othrys module carries five workarounds, each commented
in place with its upstream issue: the Local API is off with a null credentials
path so the daemon exits with `no API client section in configuration`
([#445342](https://github.com/NixOS/nixpkgs/issues/445342)); nothing writes
`/etc/crowdsec/config.yaml`, so bare `cscli`, including the bouncer's own
register unit, fails to read its config
([#469519](https://github.com/NixOS/nixpkgs/issues/469519)); `DynamicUser=true`
on units that also declare a static `crowdsec` account migrates the state
directory into `/var/lib/private` and locks the engine out of it from the second
boot on ([#520206](https://github.com/NixOS/nixpkgs/issues/520206)); and the
bouncer `Requires=` its register unit without ordering after it, so it dies at
step `CREDENTIALS` reading an API key that does not exist yet
([#526506](https://github.com/NixOS/nixpkgs/issues/526506)). A fifth defect
surfaces only later: the daily hub-update unit reloads the engine as an
unprivileged user, and the engine has no `ExecReload` to run, so the timer
leaves a failed unit on every host within a day
([#473707](https://github.com/NixOS/nixpkgs/issues/473707),
[#541058](https://github.com/NixOS/nixpkgs/issues/541058)).

The `crowdsec-test` VM check boots a fresh machine, runs the update timer,
restores a host from the broken `/var/lib/private` layout, and reboots; remove a
workaround only when that check still passes without it.
