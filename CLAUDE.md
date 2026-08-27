# CLAUDE.md

othrys.nix is a flake-parts flake exporting reusable NixOS modules under the
`othrys.*` namespace. It holds no host configurations, no secrets and no personal
data. Hosts live in a separate private fleet repository that consumes this flake
as an input.

Conventions live in [CONTRIBUTING.md](CONTRIBUTING.md), architecture in
`docs/src/architecture/`. Read those rather than restating them here. AI usage is
governed by [AI_POLICY.md](AI_POLICY.md).

## Consumer Contract

Changing any of these breaks consuming flakes.

1. **No `username` module argument.** Read the primary user from
   `config.othrys.system.user.name`. The option has no default.
1. **Guard every per-user write.** Account writes behind
   `othrys.system.users.enable`, Home Manager writes behind
   `othrys.system.users.homeManaged`, both at the attrset level, never on a leaf.
1. **`nixosModules.default` writes into upstream namespaces.** Consumers must
   also import `home-manager`, `disko`, `stylix`, `sops-nix` and `impermanence`,
   even when the matching othrys feature is off.
1. **specialArgs carry `inputs` only.** Not `username`, not `hostname`.

`flake/checks/` encodes all four. See CONTRIBUTING.md for the reasoning.

## Public Hygiene (CRITICAL)

This repository is public. Nothing here may contain:

- Real usernames, names, or email addresses (use `alice`, `example.com`)
- Domains, IPs, or hostnames of real infrastructure
- Disk serials, UUIDs, monitor descriptors, or other hardware identifiers
- Keys, keygrips, credentials, YubiKey serials, or cache tokens
- The private `secrets` input or any `git+ssh://` URL

Anything with identity belongs in the fleet repo. Examples in options use obvious
placeholders.

## Commands

```bash
just check     # nix flake check
just fmt       # treefmt
just lint      # format check, statix, deadnix
just ci        # lint plus flake check
just docs      # MdBook (build, serve, clean)
```

Host builds do not happen here. They belong to the fleet repo.
