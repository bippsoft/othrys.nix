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
