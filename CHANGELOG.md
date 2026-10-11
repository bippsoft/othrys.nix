## v0.14.0 (2026-10-11)

### BREAKING CHANGE

- wpaperd replaces hyprpaper as the wallpaper engine on
Hyprland, and othrys.desktop.wallpaper starts it on any graphical host
that enables a compositor and sets othrys.theme.wallpaper.source, niri
included. A consumer that enabled services.wpaperd for the primary
user drops that, since othrys renders its configuration, and one that
draws the wallpaper with another program sets
othrys.desktop.wallpaper.enable = false. With the Stylix export,
stylix.image follows othrys.theme.wallpaper.primary, and
othrys.theme.scheme = "wallpaper" with a run-time directory needs
primary set.
- Stylix is no longer part of nixosModules.default. A
host that uses it imports nixosModules.stylix together with the Stylix
module, and a host that does not can drop the Stylix import and its
follows line. Setting othrys.system.stylix.* without that export fails
to evaluate. othrys.system.stylix.scheme, polarity and wallpaper are
renamed to othrys.theme.scheme, othrys.theme.polarity and
othrys.theme.wallpaper.source, and the old names warn. The assets
directory is gone, and a scheme is Nix data under
othrys.theme.schemes.
- a host with othrys.hardware.nvidia.prime.enable no
longer has the NVIDIA kernel modules in its initrd and loads them from
the root filesystem. othrys.hardware.nvidia.earlyLoad = true keeps
them in the initrd.
- the othrys.desktop.noctalia options and the noctalia
flake input are removed with no replacement. A host that sets one of
the options fails to evaluate until it is deleted, and a consuming
flake that follows the input drops that line. autoLogin now requires
othrys.desktop.idle. Every graphical host runs gnome-keyring unless
othrys.desktop.keyring.enable is false.
- othrys.services.mounts.disks mounts every filesystem
with nosuid and nodev, and a disk holding setuid binaries or device
nodes sets allowSuid or allowDev. dmask and fmask accept three or four
octal digits. othrys.services.mounts.cifs no longer defaults uid and
gid to 1000 and 100, and a host without a managed account sets both.
A k3s server starts with --write-kubeconfig-mode=0600 and
--secrets-encryption, and a cluster created without secrets encryption
sets hardenedFlags = false first. othrys.services.restic refuses a
repository URL that carries a credential, which moves to
repositoryFile. othrys.services.scrutiny refuses credentials in
collector.endpoint. othrys.services.traefik refuses dashboard.insecure
beside Scrutiny, Headscale or CrowdSec on port 8080.
- Steam's remotePlay.openFirewall and
localNetworkGameTransfers.openFirewall default to false.
othrys.desktop.ashell.weatherLocation takes a city name or a latitude
and longitude and refuses the old TOML string. With u2fRequirePassword
on, every normal user needs a u2fMappings entry or a place in
u2fExemptUsers. A compositor host without the idle module runs
hypridle and locks before sleep. Violentmonkey is removed from Floorp
profiles unless a host adds it back. comma and nix-index leave the
system path where Home Manager manages the user.
- the global flake registry is no longer fetched, so an
indirect name other than nixpkgs resolves only when the host declares
it or sets othrys.system.nix.globalRegistry. nix.channel.enable is
false on a host that pins nixpkgs. Podman with dockerCompat beside
othrys Docker fails to evaluate in rootless mode as well.

### Feat

- **theme**: declare wallpapers in othrys.theme, and draw them with wpaperd on both compositors
- **theme**: add othrys.theme, and make Stylix an optional export
- **nvidia**: load the driver after the initrd on a PRIME host
- **desktop**: remove the noctalia shell module, and add a keyring option

### Fix

- **services**: mount disks nosuid, keep credentials out of restic and scrutiny URLs, and send the stale-upgrade notice
- **desktop**: lock before sleep on every compositor host, close Steam's ports, and tighten the sandboxed units
- **nix**: stop fetching the global registry, trim encrypted swap, and evaluate nested enables under their parents
- **router**: make the WAN reverse-path filter strict in effect

## v0.13.0 (2026-10-11)

### BREAKING CHANGE

- the flake no longer has a nixos-hardware input. A
consumer that follows othrys/nixos-hardware declares the input itself.
- othrys.system.git.name and email default to null, and
a host where Home Manager manages the primary user fails to evaluate
with git enabled and either unset. othrys.system.user.name accepts
only a lower-case login name. An interface's bridge and vlans must
name a netdev the host declares. othrys.apps.ai.claude-code.theme
accepts the six Claude Code themes only, and the Floorp, Vesktop,
niri, GameMode and Ghostty settings named above refuse a value their
format cannot hold. A host with a home outside /home gets its XDG and
persisted directories under that home.
- a host with othrys.system.hardening.enable boots with
slab_nomerge, page_alloc.shuffle=1 and vsyscall=none and the six
sysctls above, and a binary that needs the legacy vsyscall page stops
working until kernelParams is set without it. A host that sets both
othrys.system.kernel.enable and boot.kernelPackages fails to evaluate
until one of them goes.
- othrys.services.unbound.rpz refuses a url that is not
https, and accessControl defaults to loopback plus the network of each
bound address. othrys.services.traefik.openFirewall no longer opens
8080, and acme.storage must be under dataDir.
othrys.services.ddns.provider accepts inadyn's provider names only.
A restic repository URL with a password in it is refused and moves to
repositoryFile. An alert rule that does not parse fails the build
unless othrys.services.alerting.checkRules is false.
- AllowTcpForwarding and AllowAgentForwarding are no on
an othrys SSH server, so ssh -L, -R, -J through the host and -A are
refused until a host sets them back under services.openssh.settings.
MaxAuthTries is 3, so a client whose agent offers more keys names its
key. The key exchange, cipher and MAC lists are narrower than the
nixpkgs set. The module opens services.openssh.ports and no longer
port 22 unconditionally, and othrys.services.ssh.server.openFirewall
= false opens none. knownHosts and fail2ban.bantime reject values
their types do not cover. The client no longer sends Compression yes.
- othrys.desktop.nightLight without coordinates fails
to evaluate until geoclue.enable is set. The ashell weather module
shows nothing until weatherLocation is set. kitty accepts remote
control on its socket only. othrys.apps.ghostty.scrollbackLines is
removed in favour of scrollbackLimit, in bytes. A Hyprland host with
noctalia no longer starts hyprpaper, and noctalia hosts run
gnome-keyring. Clipboard history is kept only with ashell, and a
Hyprland host without it keeps none. Hyprland no longer exports TERM,
and nautilus is a user package installed on niri hosts as well.
- othrys.hardware.nvidia.prime.intelBusId and
nvidiaBusId have no default, and prime.enable without nvidia fails to
evaluate. i915 is no longer blacklisted unless
othrys.hardware.nvidia.blacklistIntel is set. The webcam module no
longer adds the primary user to the video group. The audio module no
longer pins USB devices to the duplex profile unless usbDuplexProfile
is set. CIFS shares mount with vers=3.1.1 and seal, so an older server
needs vers and seal set on the share. vfat mounts are owned by uid and
gid, 1000 and 100 by default, and take nosuid and nodev.
othrys.apps.obs enables othrys.services.virtualcamera and builds
without CUDA unless nvidia is enabled. A Wi-Fi network name with a
character other than a letter, digit, hyphen or space reads a
different WIFI_PSK_ variable than before.
- othrys.apps.floorp.manageSidebery is removed. The
extensions are pinned, so a new version needs a new URL and hash in
othrys.apps.floorp.extensions. The built-in password manager is off
unless builtinPasswordManager is set, and no site is exempt from
tracking protection unless trackingProtectionExemptions lists it.
- enabling othrys.system.shell.zsh makes zsh the primary
user's login shell unless othrys.system.users.defaultShell is set.
nix-clean keeps generations younger than seven days. hm-switch is
removed. A host with nixvim gets EDITOR=nvim everywhere, and one that
wants another editor sets othrys.system.defaultEditor.

### Feat

- **hardening**: add the zero-cost sysctls and kernel parameters, and close eight gaps in the unit sandbox

### Fix

- **options**: name the missing git identity and interface references, read homes from the account, and type the loose options
- **auto-upgrade**: refuse three more flags that escape the lock, and report a stale source
- **services**: tighten unbound, traefik, restic and ddns, and expose the missing printing and wireguard options
- **ssh**: open the ports sshd listens on, ship hardened server defaults, and let fail2ban follow them
- **desktop**: dispatch on the running session, make geoclue and weather explicit, and close kitty's remote control
- **hardware**: require the PRIME bus ids, stage the UPS token, tighten the mounts, and drop dead settings
- **languages**: run the registry's formatters and servers in both editors, and give JSON and YAML their own entries
- **floorp**: pin the extensions by hash, drop the unread sidebar file and the dead prefs, and stop vesktop writing Discord's settings
- **shell**: quiet the headless registry warning, make zsh the login shell, and give EDITOR one owner
- **flake**: export every infrastructure module, and say what an export needs beside it

## v0.12.0 (2026-10-11)

### BREAKING CHANGE

- per-user persistence entries are written only when
othrys.system.users.enable is on. ~/.config/hypr and ~/.config/ashell
are no longer persisted. The wifi module persists
/etc/NetworkManager/system-connections and /var/lib/NetworkManager
instead of all of /etc/NetworkManager, so files kept elsewhere under
the persisted /etc/NetworkManager are no longer mounted. zsh history
moves from ~/.zsh_history to ~/.local/share/zsh/history. Copy the old
file there once before the first login on the new generation. The
token directories named above and /var/lib/bluetooth are declared at
mode 0700, applied to the persisted directory at the next boot.
- Edit, Bash(find:*), Bash(nix eval:*) and
Bash(nix fmt:*) are no longer pre-approved by default, so Claude Code
prompts for them. A host that relied on them adds the entries to
othrys.apps.ai.claude-code.permissions.extraAllow. The format hook is
gone, and a host that wants formatting after edits registers its own.
- othrys.services.containerization.k3s.token is removed
in favour of tokenFile. openFirewall defaults to false, so a
multi-node cluster sets it. An agent or a joining server without
tokenFile fails to evaluate, as does a server beside
othrys.services.traefik that keeps the bundled Traefik.
- othrys.apps.ai.mcp.context7.token is removed, and a
host that set it fails to evaluate with the reason.

### Fix

- **services**: reach each local listener at its bound address, name the node job, and make notify fail without its token
- **grafana**: refuse the stock credential when exposed, and set the public URL, the cookie flag and sign-up
- **services**: persist the state of eight services under impermanence
- **persistence**: guard every per-user entry on the users module, close the token directories, and persist what was lost
- **claude-code**: pre-approve no bare tool, drop the dead format hook, and render the context from the host
- **users**: read the password from a secret that exists, and ship a template that can log in
- **k3s**: take the cluster token from a file only, keep the ports closed by default, and refuse the Traefik clash
- **mcp**: keep the context7 token out of the store, name the plugin Home Manager generates, and let the user read the github secret
- **floorp**: replace the personal name in the bundled sidebar profile

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
