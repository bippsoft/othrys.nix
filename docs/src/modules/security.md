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

- **U2F PAM**: password and touch for login, sudo, the greeter, polkit and the lockers
- **GPG agent**: YubiKey-backed GPG with SSH support
- **SSH keygrips**: Specific GPG keygrips for SSH authentication
- **age-plugin-yubikey**: For manual sops secret editing

### What the U2F factor actually proves

pam_u2f is inserted into the services named in `u2fServices`, which are
`login`, `sudo`, `greetd`, `polkit-1`, `hyprlock` and `swaylock` by default,
and into no other. `su` and `sshd` are left out on purpose: `su` is how root is
reached from a console with no key at hand, and `sshd` authenticates with keys
of its own. nixpkgs' global switch, which puts pam_u2f into every PAM service
on the host, is not used.

By default the control is `required`: the password and the touch must both
succeed, and the key is a second factor. That applies to the whole PAM service
and not to one user, so every account that authenticates through a listed
service needs an enrolled credential, and an account with none is locked out
of those services while other accounts keep working. The module refuses the
setting when the primary user has no mapping; enrol and test a key for every
other account that logs in, and count service and recovery accounts among them.

`othrys.services.security.yubikey.u2fRequirePassword = false` switches the
control to `sufficient`: a touch on an enrolled key satisfies the service on
its own and no password is asked for. That is authentication by possession
alone, so whoever holds the token can become root, and a token left in a laptop
is a token in somebody else's hand. It is a reasonable choice for a personal
workstation where the token lives on a keyring and the wrong one for a machine
left unattended. An account with no mapping falls through to its password, so
nothing is locked out.

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

The ban database at `/var/lib/fail2ban` is persisted under impermanence. It
holds the active bans and the per-address count that `bantime-increment`
escalates from, so a reboot neither lifts a ban nor resets an offender to the
base `bantime`.

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

Under impermanence the module persists `/var/lib/crowdsec`, which holds the
hub, the decision database and the machine credentials, together with
`/var/lib/crowdsec-firewall-bouncer-register`, which holds the bouncer's API
key. The two go together, since the engine database records the bouncer as
registered and the register unit refuses to start when that record exists
and the key file does not.

The engine runs its own Local API on loopback (`127.0.0.1:8080`), which is what
the agent authenticates against and what the bouncer reads decisions from,
machine credentials are minted on first start under
`/var/lib/crowdsec/state/`. On a router host the bouncer's own chains hook
`input` only, so the module adds a `forward` hook to the bouncer's tables there
and a banned address is no longer forwarded to the LAN. The engine watches the
sshd journal by default and Traefik's access log when that module is on, which
the crowdsec module turns on in JSON; Tailscale SSH has no CrowdSec parser and
is not watched. Enable `openFirewall` only if a remote bouncer or a
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
unprivileged user, so the timer leaves a failed unit on every host within a
day ([#473707](https://github.com/NixOS/nixpkgs/issues/473707)). The missing
`ExecReload` that went with it
([#541058](https://github.com/NixOS/nixpkgs/issues/541058)) is fixed at the
pinned nixpkgs revision, and the module no longer carries that override.

A sixth shows only during a switch. The engine's pre-start step fetches the hub
index and a failed fetch is fatal, while `After=network-online.target` protects
boot and nothing else. On a host that resolves through its own
`othrys.services.unbound`, a switch restarts the resolver and the engine in one
transaction, the fetch lands while the resolver is down, and both the engine and
the bouncer are left failed. The module orders `crowdsec.service` after
`unbound.service` whenever othrys Unbound is on, which a restart transaction
honours. `eval-router-services` reads that ordering back.

The `crowdsec-test` VM check boots a fresh machine, runs the update timer,
restores a host from the broken `/var/lib/private` layout, and reboots; remove a
workaround only when that check still passes without it.
