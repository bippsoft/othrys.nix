# CI/CD

GitHub Actions workflow for continuous integration. Each repository carries its own workflows in `.github/workflows/` (while the two share a monorepo, the interim CI at the monorepo root runs both; the per-repo workflows activate at split time).

## Pipeline

The **Build** workflow splits the flake's checks into two tiers so pull requests
get fast feedback while the exhaustive suite still gates what lands:

- **Core** (`core` job) runs on every PR/push/dispatch. The cheap, high-value
  gate: lint (pre-commit), the docs build, `eval-host-min` (a minimal
  functioning host evaluates), the four server-contract evals
  (`eval-host-headless`, `eval-host-server`, `eval-host-anonymous`,
  `eval-host-server-account`), and `impermanence-test` (the persistence and
  root-wipe invariant, the defining principle of the system). Small closures.
- **Extended** (`extended` job) runs on push to `main`, manual
  `workflow_dispatch`, and input-update PRs titled `chore(flake)`, since input
  bumps are exactly the changes that break deep surfaces. A matrix fans the suite out, one runner per check:
  `eval-default` and the two desktop evals, `enable-matrix` (every module
  enabled with defaults), and the four runtime VM tests (`restic-test`,
  `headscale-test`, `crowdsec-test`, `integration-test`).

Core builds its checks in one `nix build`; each extended matrix leg builds one check, and unchanged
derivations are pulled from the cache rather than rebuilt. `nix flake check`
locally still runs **every** check regardless of tier.

## Workflows

| File | Jobs | Purpose |
|------|------|---------|
| `build.yml` | **core** | Every PR/push: lint, docs, `eval-host-min`, the server-contract evals, `impermanence-test` (fast gate) |
| `build.yml` | **extended** | main, manual dispatch, `chore(flake)` PRs: a matrix of whole-tree evals, `enable-matrix` and the four runtime VM tests, one runner each |
| `pages.yml` | **build** + **deploy** | Builds this MdBook and publishes it to GitHub Pages on `main` (requires Pages enabled with Source = GitHub Actions) |
| `flake-inputs.yml` | **flake-inputs** | Freshness/advisory check for the flake lock (runs when `flake.{lock,nix}` change, plus weekly) |

## Disk Space

The check job uses [nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) to reclaim ~115GB of disk space on GitHub runners, replacing the default ~20GB limit.

## Cachix

CI pushes to `othrys-nix.cachix.org`, which exists to make this repository's own
builds cheap. The expensive artifacts are the extended tier's VM tests, so a run
on `main` reuses closures a previous run already built.

It is not a distribution cache. Consuming flakes gain nothing from it, since this
repository builds a shell-script wrapper and a generated options reference while
a consumer's system closure comes from nixpkgs. Nothing here adds
`othrys-nix.cachix.org` to a host's substituters, and
`othrys.system.nix.cachix.*` exists so a consumer points at their own cache
instead.

Contributors can pull from it to skip rebuilding the VM tests locally:

```nix
nix.settings = {
  substituters = ["https://othrys-nix.cachix.org"];
  trusted-public-keys = [
    "othrys-nix.cachix.org-1:0CCqJPmhMxN3PLPDEoS+vChsmWgx1pQQ4Ih4qdfqbg4="
  ];
};
```

Pushes are gated on `main` through `skipPush`, so pull-request branches read
without writing. The push filter drops source archives and man pages.
`extraPullNames` adds the `nix-community` and `hyprland` caches, so CI pulls
those prebuilt closures rather than rebuilding Hyprland from source, which is
what its deliberate refusal to follow `nixpkgs` would otherwise cost.

## Flake Checks

Defined in `flake/checks/`, with each VM test in its own file:

```nix
{{#include ../../../flake/checks/default.nix:checks}}
```

Host build checks live in the consuming fleet flake's `flake/checks.nix`.

## Running Locally

```bash
just ci       # Full CI (lint plus flake check)
just lint     # Just linting
just check    # Just flake check
```
