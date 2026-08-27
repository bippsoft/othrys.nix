<h1 align="center">othrys.nix</h1>

<p align="center">
  Reusable NixOS modules for workstations, servers and routers, behind one
  <code>othrys.*</code> option namespace.
</p>

<p align="center">
  <a href="https://github.com/bippsoft/othrys.nix/actions/workflows/build.yml"><img src="https://github.com/bippsoft/othrys.nix/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="https://bippsoft.github.io/othrys.nix/"><img src="https://img.shields.io/badge/docs-mdBook-informational" alt="Docs"></a>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos&logoColor=white" alt="NixOS Unstable"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/bippsoft/othrys.nix" alt="License"></a>
</p>

______________________________________________________________________

This flake exports NixOS modules and nothing else. There are no hosts here, no
secrets and no personal data. You import `nixosModules.default` into your own
configuration, set `othrys.*` options, and every module stays inert until you
enable it.

Modules curate capability and leave the opinions as options. The Hyprland module
knows how to float Steam dialogs and pin windows to workspaces, while you decide
the chords. The router module knows how to build a default-drop nftables ruleset
with NAT and an NFQUEUE hook, while you name the interfaces and subnets.

## Quick start

```nix
{
  inputs = {
    othrys.url = "github:bippsoft/othrys.nix";
    nixpkgs.follows = "othrys/nixpkgs";

    # Follow the inputs whose modules you import below.
    home-manager.follows = "othrys/home-manager";
    disko.follows = "othrys/disko";
    stylix.follows = "othrys/stylix";
    sops-nix.follows = "othrys/sops-nix";
    impermanence.follows = "othrys/impermanence";
  };

  outputs = inputs: {
    nixosConfigurations.myhost = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        inputs.othrys.nixosModules.default

        # Required. othrys writes into these option namespaces, so they must be
        # imported even when the matching othrys feature is off.
        inputs.home-manager.nixosModules.home-manager
        inputs.disko.nixosModules.disko
        inputs.stylix.nixosModules.stylix
        inputs.sops-nix.nixosModules.sops
        inputs.impermanence.nixosModules.impermanence

        {
          othrys.system.user.name = "alice";
          othrys.system.users = {
            enable = true;
            # A runtime path from your secrets provider. Nothing reaches the
            # Nix store. To bootstrap a host before secrets decrypt, set
            # initialHashedPassword to a `mkpasswd -m yescrypt` hash instead,
            # and move to passwordFile once the provider is up.
            passwordFile = "/run/secrets/users/alice/password";
          };
          othrys.system.nix = {
            enable = true;
            # Mandatory. The release this host was first installed at, never
            # bumped afterwards.
            stateVersion = "26.05";
            # Licensing is your policy, so it defaults to false. Most desktops
            # want it, and a host that installs no unfree package can omit it.
            allowUnfree = true;
          };
          othrys.system.locale.enable = true;
          othrys.desktop.compositors.hyprland.enable = true;
        }
      ];
    };
  };
}
```

`inputs` must reach the modules through `specialArgs`. Several modules
dereference `inputs.<name>` directly.

Two options in that example are mandatory and have no defaults, and the
remaining `othrys.*` lines are the host saying what it wants. Passwords arrive
as a runtime path from a secrets provider rather than as a string, since a
string in a module is a string in the world-readable Nix store. To bring a host
up before its provider decrypts anything, set `initialHashedPassword` to a
`mkpasswd -m yescrypt` hash and move to `passwordFile` afterwards.

## Forewarnings

Five properties of this library surprise first-time consumers. Each one fails
loudly at evaluation rather than silently at runtime, so knowing them up front
saves a round of decoding error messages.

**The primary user is an option, not a module argument.** There is no `username`
specialArg. Hosts name their user through `othrys.system.user.name`, which has
no default and is read lazily, so a headless host that enables no per-user
feature omits it entirely. Enabling a per-user feature without setting it is a
hard evaluation error. `othrys.system.nix.stateVersion` is mandatory on the same
terms, since the release a host was installed at is host identity and the
library has no business guessing it.

**Per-user state sits behind two guards, applied at the attrset level.** Account
writes require `othrys.system.users.enable`, and Home Manager writes require
`othrys.system.users.homeManaged`. The guards wrap whole attrsets rather than
leaves, since a leaf-level `mkIf` still materializes the Home Manager user and
trips NixOS's user assertions on a headless host.

**The upstream module imports are unconditional.** othrys writes into option
namespaces owned by home-manager, disko, stylix, sops-nix and impermanence, and
writing to an undeclared namespace fails evaluation regardless of `mkIf`. Import
all five even when the matching othrys feature is off.

**Enabling a module configures the capability, not the machine.** Anything
identity-shaped, meaning disk IDs, interface names, domains, monitor descriptors
and keys, ships null or neutral and arrives from your configuration.

**An input named `secrets` is read if you declare one.** othrys declares no such
input. When your flake does, `othrys.system.secrets.secretFiles` reads
`inputs.secrets.secretFiles`, which must be an attrset of names to encrypted
sops files such as `{ common = ./common.yaml; }`. Declaring no `secrets` input
is entirely fine and leaves the option empty. Declaring one that does not match
that shape fails at evaluation rather than resolving to an empty attrset, since
a typo'd input name used to surface much later as a missing sops file.

## What is in here

| Namespace | Covers |
|---|---|
| `othrys.system.*` | Identity, locale, Nix settings, kernel, systemd-networkd, bootloader, [disko](https://github.com/nix-community/disko) with LUKS and BTRFS, [impermanence](https://github.com/nix-community/impermanence), persistence, [sops-nix](https://github.com/Mic92/sops-nix) secrets, git, [Stylix](https://github.com/nix-community/stylix) theming, shells, unattended upgrades |
| `othrys.desktop.*` | [Hyprland](https://hyprland.org) through [UWSM](https://github.com/Vladimir-csp/uwsm), [niri](https://github.com/YaLTeR/niri), the [ashell](https://github.com/MalpenZibo/ashell) and [noctalia](https://github.com/noctalia-dev/noctalia-shell) shells, greetd login, idle policy, night light |
| `othrys.hardware.*` | NVIDIA with PRIME offload and shader-cache tuning, PipeWire audio, WiFi and Bluetooth, laptop profiles, USB, webcam, SMART, UPS, scanners |
| `othrys.services.*` | Router stack (nftables router and NAT, [Suricata](https://suricata.io) IDS/IPS, Kea DHCP, Unbound DNS), CrowdSec, fail2ban, SSH, Tailscale and Headscale, WireGuard, DDNS, VictoriaMetrics, VictoriaLogs, Grafana, vmalert, ntfy, restic, Traefik, Docker, Podman, k3s, mounts, printing |
| `othrys.apps.*` | [Nixvim](https://github.com/nix-community/nixvim), VSCodium, IntelliJ IDEA, Floorp, Ghostty, Kitty, yazi, gh, Claude Code and MCP servers, media apps, Steam with GameMode and MangoHud |

Every option is published in the [generated reference](https://bippsoft.github.io/othrys.nix/reference/options.html),
built from the module tree so it cannot drift.

Infrastructure modules are also exported individually, so
`inputs.othrys.nixosModules.impermanence` works if you want one without the tree.
App modules are reachable only through `default`.

## Cross-module signals

A few options exist so modules can key off each other instead of off one specific
compositor or app.

- **`othrys.desktop.graphical`** is set by every compositor module. Anything
  GUI-flavoured keys on this rather than on a compositor's own enable, so tray
  applets, GUI pinentry and clipboard tools follow the session and headless hosts
  skip the closures.
- **`othrys.desktop.lockCommand`** is the single lock authority. Idle policy, bar
  buttons and keybindings all dispatch to it.
- **`othrys.apps.languages.<lang>`** is the one "this host develops X" signal.
  Editors consume the shared toolchain rather than each installing its own copy of
  the compiler, formatter and LSP.
- **`othrys.system.impermanence.persistRoot`** is where every module keys its
  `environment.persistence` declarations. Move it and the whole tree follows.

## Two integrations worth knowing about

**Impermanence is behavioural, not aspirational.** The root subvolume is wiped at
boot, and the previous root is archived under `/btrfs_tmp/old_roots` with a
retention window rather than deleted. `old-roots` mounts that archive read-only
and copies files out. A VM test boots a real btrfs volume and asserts the whole
invariant, including that pruning cannot eat the archive.

**k3s takes manifests from Nix.** `othrys.services.containerization.k3s.manifests`
forwards straight to `services.k3s.manifests`, so cluster workloads are Nix
attribute sets deployed with the host rather than YAML applied by hand.

## Development

```bash
just check     # nix flake check (evaluation, hygiene, VM tests)
just lint      # format check, statix, deadnix
just fmt       # treefmt across the tree
just ci        # lint plus flake check
just docs      # mdBook (build, serve, clean)
```

Host builds do not happen here. They belong to the consuming flake.

CI runs a fast core tier on every pull request covering lint, the docs build,
the minimal-host and server-contract evaluations, and the impermanence VM
test. A heavier extended tier runs
on `main`, adding whole-tree evaluation, the enable-with-defaults matrix, and
runtime VM tests for CrowdSec, restic, Headscale and a full integration host.

What that buys you is narrow but real. Every module evaluates with its defaults or
is allowlisted with an assertion explaining why it cannot. The headless surface
evaluates with no managed account, with no user named at all, and with an account
but Home Manager off. Documentation includes cannot reference a missing anchor.

## Documentation

[bippsoft.github.io/othrys.nix](https://bippsoft.github.io/othrys.nix/) carries the
module reference, the consumer contract, installation and YubiKey guides, and a
recommended fleet layout. [CONTRIBUTING.md](CONTRIBUTING.md) has the module
pattern, package placement and comment conventions. AI usage is governed by
[AI_POLICY.md](AI_POLICY.md).

## Built on

[nixpkgs](https://github.com/NixOS/nixpkgs) and
[flake-parts](https://flake.parts), with
[home-manager](https://github.com/nix-community/home-manager),
[disko](https://github.com/nix-community/disko),
[impermanence](https://github.com/nix-community/impermanence),
[sops-nix](https://github.com/Mic92/sops-nix),
[Stylix](https://github.com/nix-community/stylix),
[nixvim](https://github.com/nix-community/nixvim),
[Hyprland](https://github.com/hyprwm/Hyprland),
[niri-flake](https://github.com/sodiboo/niri-flake),
[ashell](https://github.com/MalpenZibo/ashell),
[noctalia](https://github.com/noctalia-dev/noctalia-shell),
[nix-index-database](https://github.com/nix-community/nix-index-database),
[nixos-hardware](https://github.com/NixOS/nixos-hardware),
[git-hooks.nix](https://github.com/cachix/git-hooks.nix) and
[treefmt-nix](https://github.com/numtide/treefmt-nix).

## Acknowledgements

- [drduh/YubiKey-Guide](https://github.com/drduh/YubiKey-Guide) and
  [drduh/config](https://github.com/drduh/config) for the GPG hardening the
  YubiKey module and onboarding script follow
- [yokoffing/Betterfox](https://github.com/yokoffing/Betterfox) for the Firefox
  preference sets the Floorp module ships
- [jnsgruk/nixos-config](https://github.com/jnsgruk/nixos-config) for the CI
  pipeline and GitHub Actions patterns
- [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) for the AI usage
  policy this repository adapts, used under the MIT license

## License

[MIT](LICENSE)
