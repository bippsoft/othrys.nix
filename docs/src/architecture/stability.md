# Stability & Releases

othrys.nix is consumed as a flake input by fleet repositories, so option
surfaces are contracts. This page defines what consumers can rely on and how
change is signaled.

## The consumer contract

Four properties hold across every module, and changing any of them is a
breaking change. `flake/checks/` encodes all four, so a violation fails
evaluation rather than reaching a consumer.

<!-- Included from CONTRIBUTING.md, which is the canonical copy. -->

{{#include ../../../CONTRIBUTING.md:consumer-contract}}

Alongside those, the `othrys.*` option namespaces themselves and the declared
input names that consuming flakes `follows`-pin are load-bearing. See
[Host Configuration](./host-configuration.md) for what a consumer writes, and
`CONTRIBUTING.md` for the reasoning behind each rule.

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
just release          # runs the full check suite, then bumps, writes CHANGELOG.md and tags
just release minor    # the same, forcing the increment (major, minor or patch)
git push origin main v0.4.0
```

Without an argument commitizen derives the increment from the commits since the
last tag. The bump commit lands on `main`, so `main` is pushed together with the
tag.

Consumers choose their risk level:

- **Pin a tag** (`othrys.url = "github:<owner>/othrys.nix/v0.4.0"`) for
  hosts that must not drift. Upgrade deliberately by bumping the tag.
- **Track `main`** for hosts on the weekly auto-update cadence; every push
  to main has passed the CORE and EXTENDED check tiers (server contracts,
  the enable-with-defaults matrix, and the VM tests).

## What the checks guarantee

Every commit on main evaluates: the three server-contract host shapes
(named/anonymous/account-without-home-manager), both desktop stacks, every
`othrys.*.enable` flipped on with defaults (the enable matrix), the
impermanence wipe-script behavior against real btrfs, and a reboot of a VM with
an empty root that compares the machine-id, the SSH host key and the journal
directory before and after. The router stack also runs in a VM, where two LAN
clients take Kea leases, resolve a local name through Unbound and reach a WAN
host through the masquerade, while the default-drop input and forward chains are
probed from the WAN and from the other LAN. A second VM puts Suricata inline on
the router's NFQUEUE hook and shows a local rule dropping a request, then stops
Suricata and shows forwarded traffic still passing, which is the fail-open
behavior the router documents. A third VM serves a git repository to the
auto-upgrade signature gate, which refuses unsigned refs, refs signed by an
unlisted key, and a rollback.

## What the checks do not cover

- **Graphical sessions.** No check starts a compositor, so treat the first boot
  of a new desktop surface as a smoke test.
- **Secure Boot.** `eval-bootloader` evaluates every bootloader with
  `secureBoot` on and off, with and without lanzaboote imported. No check boots
  a VM under firmware Secure Boot.
- **Auto-upgrade.** The signature gate runs in a VM. The rebuild that follows it
  is never run, since the test VM has no network.
- **`aarch64-linux` beyond evaluation.** CI evaluates the server, headless and
  default host fixtures on an ARM runner. No VM test runs there, no desktop
  fixture is evaluated, and no ARM host has been booted. No other platform is
  evaluated at all.

The [Security Model](./security-model.md) lists the design limits, as opposed to
the testing limits here.
