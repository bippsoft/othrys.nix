## v0.3.1 (2026-09-04)

### Fix

- **settings**: stop generated leaves tying with upstream mkDefault

## v0.3.0 (2026-09-03)

### Feat

- **yubikey-onboard**: encrypt the master key backup and verify before deleting

## v0.2.3 (2026-09-03)

### Fix

- **yubikey-onboard**: close the gaps a default run could fall into

## v0.2.2 (2026-09-03)

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
