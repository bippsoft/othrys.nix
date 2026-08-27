# Stability & Releases

othrys.nix is consumed as a flake input by fleet repositories, so option
surfaces are contracts. This page defines what consumers can rely on and how
change is signaled.

## The consumer contract

The load-bearing surfaces are listed in the repository's consumer contract
(see [Host Configuration](./host-configuration.md)): the `othrys.*` option
namespaces, the specialArgs expectations, the required upstream module
imports, and the declared input names that fleets `follows`-pin. Changing any
of these is a breaking change.

## Option deprecation

Renamed or relocated options keep working through
`lib.mkRenamedOptionModule` aliases (for example, the former
`othrys.apps.lsp.*` names alias to `othrys.apps.languages.*`). Aliases:

- warn on use, pointing at the new name,
- are kept for **at least two tagged releases** after the rename lands,
- are removed in a release whose notes call the removal out.

Removals without a rename (a module or option deleted outright) are breaking
changes and follow the commit/release signaling below.

## Change signaling

Commit messages follow Conventional Commits (enforced by commitizen in
pre-commit):

- `feat!:` or a `BREAKING CHANGE:` footer marks anything a consumer must
  react to, so option removals, changed defaults with behavioral impact
  (e.g. the fail2ban ignoreIP default), new required options, input renames.
- `feat:`/`fix:`/`refactor:` without `!` are safe to pull blindly.

## Releases

Tags are `vMAJOR.MINOR.PATCH` (semver-ish; pre-1.0 minor bumps may carry
breaking changes, always marked as above). Cut with:

```bash
just release v0.4.0   # runs the full check suite, then tags
git push origin v0.4.0
```

Consumers choose their risk level:

- **Pin a tag** (`othrys.url = "github:<owner>/othrys.nix/v0.4.0"`) for
  hosts that must not drift. Upgrade deliberately by bumping the tag.
- **Track `main`** for hosts on the weekly auto-update cadence; every push
  to main has passed the CORE and EXTENDED check tiers (server contracts,
  the enable-with-defaults matrix, and the VM tests).

## What the checks guarantee

Every commit on main evaluates: the three server-contract host shapes
(named/anonymous/account-without-home-manager), both desktop stacks, every
`othrys.*.enable` flipped on with defaults (the enable matrix), and the
impermanence wipe-script behavior against real btrfs. What the checks do
not cover is runtime behavior of graphical sessions, so treat first boots of
new desktop surfaces as smoke tests.
