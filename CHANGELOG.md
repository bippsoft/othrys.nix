## v0.11.0 (2026-10-10)

### BREAKING CHANGE

- wheel users are no longer trusted Nix users; a host
that wants that sets othrys.system.nix.trustedUsers = ["root" "@wheel"].
nix-community.cachix.org is no longer a substituter unless
othrys.system.nix.communityCache is set, so builds that used it fetch
from cache.nixos.org or build locally. An enabled cachix with an empty
name or publicKey fails to evaluate. The nixpkgs registry entry and
NIX_PATH now point at the host's own nixpkgs.
- a host with othrys.services.containerization.docker
and rootless on, the default, no longer runs a rootful daemon or
exposes a root socket; anything that reached /var/run/docker.sock as
root on such a host uses the user's socket now. A rootful Docker on a
router host fails to evaluate until daemon.settings.iptables = false
is set.
- the primary user leaves group podman. A host that
wants a user on the rootful socket adds the group in
users.users.<name>.extraGroups itself.
- othrys.services.security.yubikey.u2fRequirePassword
defaults to true, so a host with u2fMappings asks for the password and
the touch on login, sudo, the greeter, polkit prompts and the lockers.
A host that wants a touch alone sets it to false. su no longer takes
the key. A host whose primary user has no mapping while
u2fRequirePassword is on fails to evaluate.

### Fix

- **nix**: trust root alone, make the community cache opt-in, and pin the registry to the host's nixpkgs
- **docker**: run one daemon, prune the store that is in use, and refuse rootful docker beside the router
- **scrutiny**: refuse the CrowdSec port clash on a hub alone
- **podman**: stop adding the primary user to the rootful socket's group
- **yubikey**: put pam_u2f into named services with the control the option promises

## v0.10.0 (2026-10-09)

### BREAKING CHANGE

- an ntfy server now refuses a client with no
credentials. A publisher that worked without a token needs an account
and a token from `users`, `access` and `tokensFile`, or from `ntfy
user` and `ntfy token` on the host, and `othrys.services.notify.tokenFile`
pointing at it. A host that wants the old behaviour sets
`othrys.services.ntfy.defaultAccess = "read-write"`. Under impermanence
the persisted path of ntfy and scrutiny moves from `/var/lib/<name>` to
`/var/lib/private/<name>`; a host that holds state at the old path
moves it once before the switch.
- othrys.services.tailscale.acceptRoutes defaults to
false; a host that relies on advertised subnet routes sets it to true.
A host with baseURL and no authKeyFile now warns on every evaluation
until it either sets a key file or drops baseURL.
- othrys.services.headscale.ui.agent.enable and
ui.agent.preAuthKeyFile are removed; a host that set them drops the
two lines. A host that runs Headscale beside Scrutiny or CrowdSec on
their default ports, or Headplane beside the documentation server,
fails to evaluate until one of the ports is moved. A host whose
baseDomain is the serverUrl host or a suffix of it is refused as
before, and one that only shares letters with it is now accepted.

### Fix

- **ntfy**: deny anonymous clients by default, provision access declaratively, and persist the right paths
- **tailscale**: pass the control server as --login-server and the routing flags through tailscale set
- **suricata**: reload rules on update, refuse a queue mismatch, and bind the offload unit to its interfaces
- **crowdsec**: hook the bouncer's sets on forward for a router, watch Traefik, and drop the stale reload override
- **router**: take IPv6 advertisements on the WAN, match ICMPv6 by protocol, and count what the policy drops
- **headscale**: surface the policy and the OIDC allowlists, refuse the port clashes, and drop the agent option
- **router**: render the firewall's port lists into the input chain and keep rp_filter strict on the WAN alone
- **router**: declare port forwards in a prerouting chain instead of a dnat rule that unloads the firewall

## v0.9.0 (2026-10-09)

### BREAKING CHANGE

- a systemd-boot or lanzaboote host loses the menu
editor. A host that wants it back sets
boot.loader.systemd-boot.editor = true. A host with type = "none" that
relied on the module setting canTouchEfiVariables sets it itself.
- a host with othrys.desktop.login.autoLogin and no idle
module or noctalia fails to evaluate until one of them is enabled. A
host that relied on the greeter running as the primary user, for
example to read that user's files from a greeter command, has to move
that to the session.
- a noctalia host now locks after
othrys.desktop.idle.timeouts.lock seconds, 300 by default, turns its
screen off after screenOff, and suspends after suspend when that is
set. A host that wants noctalia's previous behaviour sets the stages it
does not want to null. A host whose idle stages are out of order fails
to evaluate until they are reordered.
- /nix/var is no longer bind-mounted from the persist
root. A generation built before this release still carries that mount
unit; booted after the move, the unit fails because its source was
renamed, the host comes up on the live copy with one failed unit, and
that generation must not be used to make changes. /nix/var.install and
<persistRoot>/nix/var.migrated are kept for the operator to remove. A
host installed under the old configuration that rebooted but never
switched holds its install-time database in var.install; compare the
two before removing either.
- every host with othrys.system.impermanence.enable now
boots with the systemd initrd, and its root is wiped on every boot as
documented. A host that relied on the scripted initrd, for example
through boot.initrd.postDeviceCommands or boot.initrd.network, has to
move those settings to their systemd-initrd equivalents before taking
this release.

### Fix

- **bootloader**: turn the systemd-boot menu editor off and scope the EFI variable write
- **login**: start a session that exists, run the greeter as its own account, and tie autologin to a lock
- **idle**: declare the locker's PAM service and order the idle stages
- **persistence**: keep /nix/var on the nix subvolume and move existing hosts onto it
- **impermanence**: run the wipe unit on every host and keep it from failing the boot

## v0.8.1 (2026-10-08)

### Inputs

- **flake**: update inputs, nixpkgs e554fab to a7868a7. Also moved: aquamarine, ashell, flake-parts, home-manager, hyprgraphics, hyprland, hyprtoolkit, hyprutils, nix-index-database, nixos-hardware, nixpkgs, nixvim, noctalia, sops-nix, stylix, treefmt-nix, xdph.

## v0.8.0 (2026-10-08)

### Feat

- **ashell**: show battery, brightness, and network on a laptop
- **nvidia**: make the driver package an option

## v0.7.0 (2026-09-19)

### BREAKING CHANGE

- the boot menu now keeps the 5 newest generations. Set
othrys.system.bootloader.maxGenerations to another number, or to null for the
bootloader's own default. A host that sets boot.loader.limine.maxGenerations or
a configurationLimit itself has to move that value to this option, since the two
definitions now conflict.

### Feat

- **bootloader**: limit the generations kept on the boot partition

## v0.6.0 (2026-09-19)

### Feat

- **rustdesk**: add forceX11 to start the launcher through XWayland

### Fix

- **rustdesk**: persist the client's own config directory

## v0.5.2 (2026-09-19)

### Fix

- **persistence**: migrate a running host's machine-id on its first switch

## v0.5.1 (2026-09-19)

### Fix

- **dev-shells**: give consuming flakes a shell without the repository hooks
- **suricata**: end a failing start in failed and report it
- **crowdsec**: start after the local resolver during a switch
- **suricata**: state modbus and dnp3 as off so their rules are dropped

## v0.5.0 (2026-09-18)

### BREAKING CHANGE

- every router behind websecure now refuses TLS below 1.2 and
sends HSTS, nosniff, and X-Frame-Options SAMEORIGIN, and with ACME on a
connection by IP address or unknown server name is refused. Set tls.minVersion
= null, tls.sniStrict = false, or securityHeaders.enable = false to keep the
old behaviour, or change the single header options.
- secureBoot = true no longer evaluates with type "grub" or "none". With type "systemd-boot" it now requires the consuming flake to add a lanzaboote input and import lanzaboote.nixosModules.lanzaboote.

### Feat

- **flake**: evaluate the library on aarch64-linux
- **auto-upgrade**: verify the flake ref's signature before switching
- **templates**: add a default host template
- **ssh**: distribute known hosts and set safe client defaults
- **traefik**: set a TLS floor and security headers by default
- **hardening**: add an opt-in kernel and sysctl hardening profile
- **bootloader**: support Secure Boot on systemd-boot through lanzaboote

### Fix

- **niri**: import the niri module from this flake's own inputs

### Refactor

- **auto-upgrade**: take the verify unit's sandbox from the shared baseline
- **services**: share one sandboxing baseline across custom units

## v0.4.0 (2026-09-18)

### BREAKING CHANGE

- othrys.apps.gaming.steam no longer opens TCP and UDP 27015 by
default. A host that runs a Source dedicated server sets
dedicatedServer.openFirewall = true.
- every backup now ends with restic check reading a random 5%
of the pack data. Set runCheck = false, or change checkOpts, on backups where
that read costs too much.

### Feat

- **checks**: scan commits for secrets with gitleaks
- **restic**: verify the repository after each backup by default
- **steam**: add shader pre-caching thread options

### Fix

- **dev-shells**: install the same hooks the flake check runs
- **notify**: write the header file under XDG_RUNTIME_DIR
- **nix**: accept allowUnfreePredicate on an external nixpkgs instance
- **alerting**: fail the render unit when the token file is missing
- **alerting**: reject a token that would break the rendered YAML
- **checks**: drop the drvPath string context in mkHostEval
- **persistence**: keep SSH host keys on the persist volume
- **persistence**: persist /etc/machine-id across the root wipe
- **steam**: expose the installed package through the read-only package option
- **steam**: drop the session-wide STEAM_EXTRA_COMPAT_TOOLS_PATHS
- **steam**: stop opening the dedicated server ports by default
- **floorp**: use the navbar value Firefox 155 accepts for default_area

## v0.3.1 (2026-09-04)

### Fix

- **settings**: stop generated leaves tying with upstream mkDefault

## v0.3.0 (2026-09-03)

### Known issue

- A host that sets `othrys.services.ntfy.listenAddress` to anything off loopback
  fails evaluation on this tag. Fixed in v0.3.1.

### Feat

- **yubikey-onboard**: encrypt the master key backup and verify before deleting

## v0.2.3 (2026-09-03)

### Known issue

- A host that sets `othrys.services.ntfy.listenAddress` to anything off loopback
  fails evaluation on this tag. Fixed in v0.3.1.

### Fix

- **yubikey-onboard**: close the gaps a default run could fall into

## v0.2.2 (2026-09-03)

### Known issue

- A host that sets `othrys.services.ntfy.listenAddress` to anything off loopback
  fails evaluation on this tag. Fixed in v0.3.1.

### Fix

- **settings**: make passthrough overrides work as documented

## v0.2.1 (2026-09-03)

### Fix

- **modules**: guard every remaining per-user home-manager write

### Refactor

- **users**: route per-user config through one guarded option

## v0.2.0 (2026-08-28)

### BREAKING CHANGE

- othrys.apps.rustdesk no longer opens TCP 21114 through 21119
or UDP 21116. Hosts needing direct IP access set openFirewall, which opens
TCP 21118 alone.
- GITHUB_PAT is no longer exported into interactive shells.
Tooling that read it from the environment needs its own source for the token.
- othrys.system.secrets.ageKeyFile is renamed to
ageIdentityStubs, with no compatibility alias. Identities holding key material
move to the new ageIdentityFile option.
- credential *File options no longer accept path literals or
store paths. Pass a runtime path string such as "/run/secrets/name".
- othrys.system.users.initialPassword is removed. Use
initialHashedPassword with a `mkpasswd -m yescrypt` hash, or passwordFile.
users.mutableUsers is no longer inferred and defaults to false.
- othrys.system.nix.allowUnfree now defaults to false. Hosts
that install unfree packages must opt in.
- othrys.system.nix.stateVersion has no default and must be
set per host.

### Feat

- **security**: add a U2F password requirement option
- **apps**: add openFirewall to rustdesk and localsend
- **ai**: run the GitHub MCP server locally with a file-backed token
- **secrets**: rename ageKeyFile and add a runtime-path identity form
- **lib**: add a store-rejecting secret path type and apply it repo-wide
- **users**: replace initialPassword with initialHashedPassword
- **nix**: default allowUnfree to false and assert on external pkgs
- **system**: require an explicit stateVersion

### Fix

- **treefmt**: stop formatting the generated CHANGELOG.md
- **impermanence**: derive the home directory group from the user config
- **impermanence**: scope IFS and null-delimit the retention loop
- **git**: apply pull.rebase at mkDefault
- **secrets**: validate the optional secrets flake input
- **ai**: drop the just allow rule and expose the permission mode
- **notify**: pass the token by header file and sandbox notify-failure@
- **alerting**: carry the notify token into the alertmanager-ntfy bridge

### Refactor

- **gaming**: move curated gamemode defaults into config at mkDefault
- widen types.attrs passthroughs to attrsOf anything

## v0.1.0 (2026-08-27)

### Feat

- initial public release of the othrys.nix module library
