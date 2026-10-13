# AGENTS.md

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
   `environment.persistence`. One export applies each registry and its guard,
   `nixosModules.home` for the first and `nixosModules.impermanence` for the
   second.
1. **`nixosModules.default` writes into no upstream namespace.** A host built
   from it alone imports no other module. Five exports are optional, and a
   host imports each together with the upstream module it configures.
   `nixosModules.home` goes with Home Manager, `nixosModules.stylix` with
   Stylix, `nixosModules.disko` with disko, `nixosModules.secrets` with
   sops-nix and `nixosModules.impermanence` with impermanence.
   `nixosModules.full` is `default` with all five and the five upstream
   modules, taken from this flake's own lock.
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

## Agent Sessions

Start the session inside `nix develop`. The shell provides `nixd`, `treefmt`
and the three commands below, and the plugin in `.opencode/plugins/` refuses
every write when it cannot find them. The session is already in the shell, so
call each command by its name. `nix develop` is denied inside a session.

- `check-one <name>` builds one check named in `flake/checks/default.nix`. It
  is the only way an agent evaluates this flake. `nix build`, `nix eval`,
  `nix flake check` and `just` are denied, since evaluating every check at
  once has exhausted a workstation's memory. One check runs at a time, and a
  second call fails while the first holds the lock. A sub-agent never
  evaluates.
- `hygiene-scan` reads what is staged, or the files named, for text that the
  section above forbids and a pattern can prove. It runs before every write
  and again as a commit hook. A hostname or a person's name passes it, so read
  for those yourself.
- `module-coverage` says when a module changed on the branch while no page
  under `docs/src/` or no check under `flake/checks/` did.

A change to a module is finished when its check and its page changed with it.

An agent commits on a branch with `git commit --no-gpg-sign`, one logical
change per commit. It never pushes, tags, signs or merges. Every commit on
`main` carries a maintainer's signature, which the maintainer adds when landing
the branch.

`.opencode/` holds the agents, skills and commands for this repository, and
`docs/src/development/agents.md` describes them.

## Writing for the History

- **Commits** follow the Commit Conventions in CONTRIBUTING.md. The subject is
  lowercase after the prefix, imperative and without a full stop, as in
  `fix(ssh): refuse an empty port list`. This form holds over any style a
  session brings from elsewhere. The body says what the code did before, what
  it does now and why, in plain sentences wrapped at 72 columns. A
  `BREAKING CHANGE:` footer says what a consumer must do.
- **Issues** state one defect under four headings, `Observed`, `Mechanism`,
  `Fix shape` and `Acceptance`, in 80 to 150 words, with a lowercase sentence
  for a title.
- **Subject matter** is the defect and the change. A commit, an issue or a
  pull request never says how the defect came to light or which process
  produced the change.
- **No tool attribution.** A commit message carries no trailer or footer that
  names a tool or a session. An outside contributor discloses AI use in the
  pull request, as [AI_POLICY.md](AI_POLICY.md) requires.

## Commands for People

```bash
just check            # nix flake check
just check-one NAME   # one check, under the same limits an agent gets
just fmt              # treefmt
just lint             # format check, statix, deadnix
just ci               # lint plus flake check
just docs             # MdBook (build, serve, clean)
```

Host builds do not happen here. They belong to the fleet repo.
