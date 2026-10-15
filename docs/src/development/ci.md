# CI/CD

GitHub Actions runs the flake's checks. The workflows live in
`.github/workflows/`.

## Pipeline

The **Build** workflow splits the flake's checks into two tiers. Both run on
every pull request, every push to `main` and every manual dispatch, so the core
tier reports early while the whole suite still gates what lands:

- **Commit signatures** (`signatures` job) verifies every commit of a push
  to `main`, and of a pull request from a branch of this repository, against
  the keys tracked under `keys/`. It is skipped for a pull request from a fork.
- **Core** (`core` job) runs on every PR/push/dispatch and builds its checks
  in one `nix build`. They are the lint hooks, the secret scan, the docs
  build, the host evaluations and read-backs in the table below, and
  `impermanence-test`. Their closures are small.
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
  `integration-test`, `listeners-test`, `impermanence-reboot-test`,
  `impermanence-wipe-test`, `wallpaper-test`, `keyring-test`,
  `yubikey-onboard-dry-run`).
- **Extended verdict** (`extended-ok` job) turns the matrix into one status
  that branch protection can require. It passes only when every matrix leg
  succeeded, so a failed, cancelled or skipped leg fails it.

| Check | What it covers |
|-------|----------------|
| `pre-commit-check` | The eight commit hooks, run over the whole tree |
| `secret-scan` | gitleaks over every tracked file |
| `docs` | The MdBook build, with the generated options reference injected |
| `docs-includes` | Every include, anchor, relative link and heading fragment under `docs/src` resolves |
| `eval-host-min` | A minimal functioning host evaluates |
| `eval-host-headless`, `eval-host-server`, `eval-host-anonymous`, `eval-host-server-account` | The four server-contract host shapes, each with no Home Manager module imported |
| `eval-host-app-no-hm`, `eval-host-app-no-hm-full` | A slice of the app and desktop modules, and all of them, each on a host with an account that Home Manager does not manage |
| `eval-pairs` | Every conflict or requirement between two modules or two options, each matched by a fragment of its assertion message |
| `eval-contract` | No module file takes `username` or `hostname`, only `modules/system/home.nix` writes `home-manager.users`, only `modules/system/impermanence.nix` writes `environment.persistence`, and the fixtures and the template pass `inputs` alone or nothing |
| `eval-inputs` | A host handed no `specialArgs` enables ashell, Hyprland, nixvim and comma, gets each from this flake's lock, and gets the package it sets through a `package` option |
| `ci-coverage` | Every check is named by a job in `build.yml`, and every name there is a check |
| `eval-bootloader` | Every bootloader type with `secureBoot` off and on |
| `eval-host-hardening`, `eval-host-hardening-hibernate` | The hardening profile's values, and its hibernation assertion |
| `eval-impermanence` | What the impermanence module writes into the initrd |
| `eval-persistence` | What the app and desktop modules persist, with a managed account and without one |
| `eval-service-state` | What the service modules persist under impermanence |
| `eval-nix` | What the nix module trusts and pins |
| `eval-shell` | The login shell, the editor variables and the aliases |
| `eval-types` | The values the option types refuse, and the git identity and bridge or vlan reference assertions |
| `eval-exports` | The export list in `flake/modules.nix`, held to the module tree |
| `eval-optional-exports` | A host with `default` and no upstream module at all, a managed account rejected without `nixosModules.home`, an account Home Manager does not manage accepted without it, a host built from `nixosModules.full`, impermanence on a device named by hand, the rejection of impermanence without its export, and what the `disko`, `secrets` and `impermanence` exports write beside their upstream modules |
| `eval-template` | The `nix flake init` template, instantiated with only the inputs a consumer has |
| `eval-dev-shells` | The hooks each dev shell installs |
| `eval-auto-upgrade` | The evaluation-time rules of the auto-upgrade verify gate |
| `eval-ssh`, `eval-ssh-settings` | The known hosts and client defaults, and the server's ports, firewall, jail and hardened defaults |
| `eval-pam` | Which PAM services take the YubiKey, and with what control |
| `eval-traefik` | The Traefik TLS floor and header defaults |
| `eval-router`, `eval-router-services` | The router's rendered ruleset, and the start-up defaults of Suricata and CrowdSec |
| `eval-headscale`, `eval-tailscale` | What the two modules render, pass to the daemon and refuse |
| `eval-exposure` | What ntfy, Scrutiny and the two Victoria stores expose and persist |
| `eval-grafana` | What the Grafana module serves and refuses |
| `eval-listen` | Where the metrics, logs, dashboard and alerting modules find each other |
| `eval-services` | What the smaller service modules pass upstream and refuse |
| `eval-k3s`, `eval-containers` | What k3s opens and requires, and what the container modules run and prune |
| `eval-gaming` | The `gamemode` group GameMode needs for its root helpers, the GameMode defaults, the ntsync driver and device access with and without Steam, and the ntsync rename |
| `eval-hardware`, `eval-nvidia` | What the hardware, CPU, mount and disk modules write, and which NVIDIA driver a host gets |
| `eval-desktop`, `eval-lock`, `eval-login` | What the desktop modules and terminals write, the session lock, and what greetd is handed |
| `eval-vicinae` | The Vicinae settings, theme, unit and persisted directories, the launcher chord on Hyprland and Niri with Vicinae on and off, and the hosts it writes nothing to |
| `eval-keyring` | The Secret Service provider each setting of `othrys.desktop.keyring` selects, the keyring written without a password, and the combinations the module refuses |
| `eval-theme` | The palette, fonts and schemes of `othrys.theme` on hosts with no Stylix module, and what the Stylix adapter hands over and takes back |
| `eval-wallpaper` | The wallpaper daemon's configuration for each form of `othrys.theme.wallpaper.source`, the hosts that get no daemon, and the image the Stylix adapter is handed |
| `eval-languages` | The binaries nixvim and VSCodium take from the language registry |
| `eval-floorp`, `eval-rustdesk` | The Floorp and Discord settings, and what RustDesk persists and launches |
| `eval-chromium` | Chromium's user package, wrapper arguments, extension manifests, persistence, registry guards and typed refusals |
| `eval-claude-code` | The settings, pre-approved tools, skills and context the AI modules hand Claude Code |
| `eval-opencode` | The sharing modes, settings override and type refusals, and the permission map, skills, context, MCP servers and Ollama provider the AI modules hand OpenCode |
| `opencode-config` | The committed OpenCode configuration, which is the skill names, the agent and command descriptions, the permission values and the agents each file names |
| `eval-gh` | The `gh` settings and credential helper, the wrapper a token file installs, and the read-only commands pre-approved for Claude Code |
| `yubikey-onboard-builds` | The onboarding script's package, whose build runs shellcheck and `bash -n` over the script |
| `impermanence-test` | A VM test of the wipe script and the persistence invariant |

**Core on ARM** (`core-aarch64` job) runs on the same events on an
`ubuntu-24.04-arm` runner. It builds the portable host evaluations for
`aarch64-linux`, which is every check named in `portableChecks` in
`flake/checks/default.nix`. It is not required by branch protection.

**Extended** (`extended` job) runs on push to `main`, on manual dispatch, and
on a pull request that changes `flake.nix` or `flake.lock` or whose title
starts with `chore(flake)`, since input bumps are the changes that break deep
surfaces. A matrix gives each check its own runner. The `extended-ok` job
reports one status for branch protection and counts a skipped matrix as a
pass.

| Check | What it covers |
|-------|----------------|
| `eval-default`, `eval-host-desktop`, `eval-host-desktop-niri` | The whole module tree with defaults, and the two desktop stacks |
| `eval-ashell` | The bar's generated config for a desktop and a laptop |
| `enable-matrix` | Every `othrys.*.enable` option turned on with defaults, where an expected failure has to carry the assertion message the allowlist names |
| `restic-test` | A backup, a restore and the integrity check, in a VM |
| `headscale-test` | A Tailscale client registering against Headscale |
| `auto-upgrade-test` | The signature gate in front of the unattended upgrade |
| `crowdsec-test` | The CrowdSec engine and bouncer on a fresh host |
| `router-test`, `router-ips-test` | The router, Kea and Unbound on a virtual network, and Suricata inline on the NFQUEUE hook |
| `integration-test` | A booted machine with a representative set of modules |
| `listeners-test` | The listening sockets and the firewall accept rules of a booted server, compared with a list written in the test |
| `impermanence-reboot-test`, `impermanence-wipe-test` | Host identity across a reboot with an empty root, and the wipe unit booted from a btrfs root |
| `wallpaper-test` | The wallpaper daemon's unit, its rendered configuration and the directory built from a list of images, on a booted machine |
| `keyring-test` | A secret stored and read back through the Secret Service on two booted machines, one with a gnome-keyring store that has no password and one with `pass` and a software OpenPGP key |
| `yubikey-onboard-dry-run` | The packaged onboarding script's dry run as an unprivileged user, which must take the `unshare -Urm` path, exit 0, write nothing, and name a summary directory outside the working directory |

Unchanged derivations are pulled from the cache and not rebuilt.
`nix flake check` locally runs every check regardless of tier. That includes
`comment-hygiene`, `contract-guards` and `treefmt` as checks of their own,
which no workflow job builds by name, since `pre-commit-check` runs all three
as hooks over the whole tree.

The workflow lists its checks by name, so a check added to `flake/checks/`
and left out of `build.yml` would be built by no job. The `ci-coverage` check
fails on that. It reads the attribute names of `checks.x86_64-linux`, reads
`build.yml` for every `checks.x86_64-linux.<name>` installable and every item
of the extended matrix, and fails naming any check that no job builds and any
listed name that is not a check. The three checks above are named in
`localOnly` in `flake/checks/ci-coverage.nix`, and an entry there that a job
does build, or that names no check, fails as well. A new check therefore
needs a line in `build.yml` or an entry in `localOnly` with its reason.

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
| `build.yml` | **core** | Every PR/push: lint, docs, `docs-includes`, `ci-coverage`, `eval-host-min`, the server-contract and app-contract evals, `eval-pairs`, `eval-contract`, `eval-inputs`, `eval-bootloader`, `impermanence-test` (fast gate) |
| `build.yml` | **core-aarch64** | Every PR/push: the portable host evaluations for `aarch64-linux` on an ARM runner |
| `build.yml` | **extended** | Every PR/push: a matrix of whole-tree evals, `enable-matrix` and the runtime VM tests, one runner each |
| `build.yml` | **extended-ok** | Every PR/push: one status for the matrix, passing only when every leg succeeded |
| `pages.yml` | **build** + **deploy** | Builds this MdBook and publishes it to GitHub Pages on `main` (requires Pages enabled with Source = GitHub Actions) |
| `flake-inputs.yml` | **flake-inputs** | Health check of the nixpkgs pins in the flake lock, which covers the branch they track, their age and whether the release is supported. It runs when `flake.{lock,nix}` change and weekly, and it does not scan for security advisories |
| `update-inputs.yml` | **update** | Weekly `nix flake update`, opened as a `chore(flake)` pull request and never merged automatically |
| `scorecard.yml` | **analysis** | OpenSSF Scorecard on `main`, weekly, and on branch protection changes. Publishes the score behind the README badge and uploads findings to code scanning |

`.github/dependabot.yml` raises weekly PRs that move the sha pins of the actions
these workflows use. Nix inputs are left to `update-inputs.yml`.

## Disk Space

The `core` and `extended` jobs use [nothing-but-nix](https://github.com/wimpysworld/nothing-but-nix) to reclaim ~115GB of disk space on GitHub runners, replacing the default ~20GB limit.

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

This repository holds no hosts, so host build checks belong to the consuming fleet flake.

## Documentation Includes

mdbook logs an include it cannot read, renders the page with nothing in its
place and exits 0. The `docs-includes` check is what fails instead. It runs
`flake/checks/docs-includes.py` over `docs/src`, which resolves each include
relative to the page that holds it and reports the page, the directive and the
reason when the file is missing, when the named anchor has no `ANCHOR:` and
`ANCHOR_END:` pair in the target, or when a line range starts past the end of
the file. The same pass reports a relative link to a page that does not exist
and a `#fragment` that matches no heading in the page it points at.

The `docs` check runs the resolver again before `mdbook build`, with the
generated options reference in place, so links into that page are resolved
there. The script needs only Python and runs from a checkout:

```bash
python3 flake/checks/docs-includes.py docs/src --generated reference/options.md
```

## Running Locally

```bash
just ci       # Full CI (lint plus flake check)
just lint     # Just linting
just check    # Just flake check
```
