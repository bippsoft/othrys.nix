# CI/CD

GitHub Actions workflow for continuous integration. Each repository carries its own workflows in `.github/workflows/` (while the two share a monorepo, the interim CI at the monorepo root runs both; the per-repo workflows activate at split time).

## Pipeline

The **Build** workflow splits the flake's checks into two tiers. Both run on
every pull request, every push to `main` and every manual dispatch, so the core
tier reports early while the whole suite still gates what lands:

- **Core** (`core` job) runs on every PR/push/dispatch. The cheap, high-value
  gate: lint (pre-commit), `secret-scan` (gitleaks over every tracked file), the docs build, `eval-host-min` (a minimal
  functioning host evaluates), the four server-contract evals
  (`eval-host-headless`, `eval-host-server`, `eval-host-anonymous`,
  `eval-host-server-account`), `eval-bootloader` (every bootloader type with
  `secureBoot` off and on), `eval-host-hardening` and
  `eval-host-hardening-hibernate` (the hardening profile's values read back,
  and its hibernation assertion), `eval-traefik` (the Traefik TLS floor and
  header defaults read back), `eval-ssh` (the known hosts and client defaults
  read back), `eval-ssh-settings` (the SSH server's ports, firewall, jail and
  hardened defaults read back), `eval-template` (the `nix flake init` template instantiated with
  only the inputs a consumer has), `eval-router-services` (the start-up defaults
  of Suricata and CrowdSec read back), `eval-dev-shells` (the hooks each dev
  shell installs read back), `eval-rustdesk` (what the RustDesk module persists
  and launches), `eval-nvidia` (which NVIDIA driver and kernel modules a host
  gets), `eval-persistence` (what the app and desktop modules persist, read
  back on an impermanence host with a managed account and on one without),
  `eval-languages` (the binaries nixvim and VSCodium take from the language
  registry), `eval-hardware` (what the hardware, mount and disk modules
  write), `eval-types` (the values the option types refuse, and the git
  identity and bridge or vlan reference assertions), and `impermanence-test` (the persistence and
  root-wipe invariant, the defining principle of the system). Small closures.
- **Core on ARM** (`core-aarch64` job) runs on every PR/push/dispatch on an
  `ubuntu-24.04-arm` runner. It builds the portable host evaluations for
  `aarch64-linux`, which is every check named in `portableChecks` in
  `flake/checks/default.nix`. It is not required by branch protection.
- **Extended** (`extended` job) runs on every PR/push/dispatch. Neither the
  changed paths nor the pull request title decides whether it runs. A matrix fans the suite out, one runner per check:
  `eval-default` and the two desktop evals, `eval-ashell` (the bar's generated
  config for a desktop and a laptop), `enable-matrix` (every module
  enabled with defaults), and the runtime VM tests (`restic-test`,
  `headscale-test`, `auto-upgrade-test`, `crowdsec-test`, `router-test`, `router-ips-test`,
  `integration-test`, `impermanence-reboot-test`, `impermanence-wipe-test`).
- **Extended verdict** (`extended-ok` job) turns the matrix into one status
  that branch protection can require. It passes only when every matrix leg
  succeeded, so a failed, cancelled or skipped leg fails it.

Core builds its checks in one `nix build`; each extended matrix leg builds one check, and unchanged
derivations are pulled from the cache rather than rebuilt. `nix flake check`
locally still runs **every** check regardless of tier.

Branch protection on `main` requires two statuses, `Core checks` and
`Extended verdict`. That requirement is a repository setting, and the workflow
only reports them.

A newer push to a pull request cancels the run before it. A run on `main` is
never cancelled, since its concurrency group is keyed on the commit, so a
release commit keeps its run when another push follows it.

## Permissions

Every workflow starts from `permissions: contents: read`, and a job that needs
more declares it on itself. The `deploy` job of `pages.yml` holds `pages: write`
and `id-token: write`, while the `build` job beside it holds read access only.
The `analysis` job of `scorecard.yml` holds `security-events: write` and
`id-token: write`. The `update` job of `update-inputs.yml` holds
`contents: write` and `pull-requests: write`. Every `actions/checkout` step sets
`persist-credentials: false`, so no job leaves the token in `.git/config`. No
job reads the pull request title or any other event text.

## Workflows

| File | Jobs | Purpose |
|------|------|---------|
| `build.yml` | **core** | Every PR/push: lint, docs, `eval-host-min`, the server-contract evals, `eval-bootloader`, `impermanence-test` (fast gate) |
| `build.yml` | **core-aarch64** | Every PR/push: the portable host evaluations for `aarch64-linux` on an ARM runner |
| `build.yml` | **extended** | Every PR/push: a matrix of whole-tree evals, `enable-matrix` and the runtime VM tests, one runner each |
| `build.yml` | **extended-ok** | Every PR/push: one status for the matrix, passing only when every leg succeeded |
| `pages.yml` | **build** + **deploy** | Builds this MdBook and publishes it to GitHub Pages on `main` (requires Pages enabled with Source = GitHub Actions) |
| `flake-inputs.yml` | **flake-inputs** | Freshness/advisory check for the flake lock (runs when `flake.{lock,nix}` change, plus weekly) |
| `scorecard.yml` | **analysis** | OpenSSF Scorecard on `main`, weekly, and on branch protection changes. Publishes the score behind the README badge and uploads findings to code scanning |

`.github/dependabot.yml` raises weekly PRs that move the sha pins of the actions
these workflows use. Nix inputs are left to `update-inputs.yml`.

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
