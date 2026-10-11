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

<!-- ANCHOR: consumer-contract -->

1. **No `username` module argument.** Read the primary user from
   `config.othrys.system.user.name`. The option has no default.
1. **Guard every per-user write.** Account writes behind
   `othrys.system.users.enable`, at the attrset level, never on a leaf. Home
   Manager configuration goes to `othrys.internal.homeConfig` and persistent
   paths go to `othrys.internal.persist`, never to `home-manager.users` or
   `environment.persistence`. Each registry applies its guard once.
1. **`nixosModules.default` writes into one upstream namespace.** Consumers
   must also import `home-manager`, even when no othrys module configures the
   user. A consumer who wants Stylix imports `nixosModules.stylix` and the
   Stylix module together. One who wants the disko layout imports
   `nixosModules.disko` and the disko module, one who wants the sops plumbing
   imports `nixosModules.secrets` and the sops-nix module, and one who wants an
   ephemeral root imports `nixosModules.impermanence` and the impermanence
   module.
1. **specialArgs carry `inputs` or nothing.** Modules read two names from it,
   `nixpkgs` for the registry pin and the optional `secrets`. Not `username`,
   not `hostname`.

<!-- ANCHOR_END: consumer-contract -->

`flake/checks/` encodes all four. CONTRIBUTING.md is the canonical copy and
carries the reasoning. The block above is a deliberate duplicate, kept inline
because an agent reads this file automatically and would otherwise have to be
told to go and fetch the contract. A `contract-mirror` pre-commit hook diffs
the two anchored regions, so the copies cannot drift apart silently.

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
