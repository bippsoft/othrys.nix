# Security

Security modules under `othrys.services.security.*`. Located in `modules/services/security/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Sudo | `othrys.services.security.sudo` | sudo with a password for wheel, `use_pty` and a credential timeout |
| Polkit | `othrys.services.security.polkit` | Turns on polkit and adds no rules |
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
setting while any normal user of the host has no mapping, the primary user and
every other account declared with `isNormalUser` alike. An account that never
authenticates through a listed service, such as one reached over SSH alone, is
named in `u2fExemptUsers` and the check passes it over. root is not checked,
since `su` stays off the list as the way to it. Enrol and test a key for every
account that logs in, and count service and recovery accounts among them.

`othrys.services.security.yubikey.u2fRequirePassword = false` switches the
control to `sufficient`: a touch on an enrolled key satisfies the service on
its own and no password is asked for. That is authentication by possession
alone, so whoever holds the token can become root, and a token left in a laptop
is a token in somebody else's hand. It is a reasonable choice for a personal
workstation where the token lives on a keyring and the wrong one for a machine
left unattended. An account with no mapping falls through to its password, so
nothing is locked out.

### On nix-darwin

`darwinModules.default` carries the module. The GnuPG configuration, the
`sshcontrol` keygrips and the gpg-agent with SSH support are the same Home
Manager configuration as on NixOS, and Home Manager runs the agent as the
user's launchd agent. `pinentryPackage` defaults to `pinentry_mac` there,
and to `pinentry-curses` on a Mac with `othrys.desktop.graphical` off.
macOS reads the token through its own smart card stack, so there is no
pcscd or udev rule to set up. The tools are installed system-wide, without
`pam_u2f`.

The U2F login is NixOS only, and a darwin host with a `u2fMappings` entry is
refused. Touch ID for sudo stays the host's own choice through
`security.pam.services.sudo_local.touchIdAuth`, since it lets a fingerprint
alone pass sudo while `u2fRequirePassword` defaults to two factors.

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

One jail, `sshd`, which is defined only on a host that runs the OpenSSH server.
It reads the journal with the `aggressive` filter mode and bans an address after
`maxretry` failures within ten minutes. The ban lasts `bantime` the first time
and grows with each repeat up to 48 hours.

The jail names no port of its own. It bans on the ports in
`services.openssh.ports`, so a server moved off port 22 through
`othrys.services.ssh.server.ports` is covered without further configuration.
The filter matches more failed logins when sshd logs at `VERBOSE`, which is the
level the SSH module sets.

`bantime` takes a number of seconds or a number with one of the suffixes `s`,
`m`, `h`, `d`, `w`, `mo` and `y`. Any other string is rejected at evaluation.

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
is not watched, and the module warns when `othrys.services.tailscale.ssh` is
on beside it. Enable `openFirewall` only if a remote bouncer or a
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

### Upstream module

nixpkgs rewrote `services.crowdsec` in October 2026. The rewrite starts on a
fresh host without help, so the workarounds this module carried for the old one
are gone. Three things remain.

The rewrite moved the data directory from `/var/lib/crowdsec/state` to
`/var/lib/crowdsec/data`. The module pins the old path, which keeps the decision
database, the hub and the machine credentials of a host that ran the old module.

The rewrite also dropped `services.crowdsec.openFirewall`. The othrys option of
that name now opens the port of
`services.crowdsec.settings.config.api.server.listen_uri` itself. Since that
address is on loopback by default, the option matters only beside a changed
`listen_uri`.

The hub index is fetched by `crowdsec-setup.service`, and the engine waits on
that unit. `After=network-online.target` protects boot and nothing else. On a
host that resolves through its own `othrys.services.unbound`, a switch can
restart the resolver and the setup unit in one transaction, and the fetch then
lands while the resolver is down. The module orders `crowdsec-setup.service`
after `unbound.service` whenever othrys Unbound is on, which a restart
transaction honours. `eval-router-services` reads that ordering back.

The `crowdsec-test` VM check boots a fresh machine, runs the update timer and
reboots.
