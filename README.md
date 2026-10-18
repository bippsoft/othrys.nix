<p align="center">
  <img src="docs/src/images/othrys-header.svg" alt="Mount Othrys" width="480">
</p>

<h1 align="center">othrys.nix</h1>

<p align="center">
  Reusable NixOS modules for workstations, servers and routers, behind one
  <code>othrys.*</code> option namespace.
</p>

<p align="center">
  <a href="https://github.com/bippsoft/othrys.nix/actions/workflows/build.yml"><img src="https://github.com/bippsoft/othrys.nix/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="https://scorecard.dev/viewer/?uri=github.com/bippsoft/othrys.nix"><img src="https://api.scorecard.dev/projects/github.com/bippsoft/othrys.nix/badge" alt="OpenSSF Scorecard"></a>
  <a href="https://bippsoft.github.io/othrys.nix/"><img src="https://img.shields.io/badge/docs-mdBook-informational" alt="Docs"></a>
  <a href="https://nixos.org"><img src="https://img.shields.io/badge/NixOS-unstable-blue?logo=nixos&logoColor=white" alt="NixOS Unstable"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/bippsoft/othrys.nix" alt="License"></a>
</p>

______________________________________________________________________

This flake exports NixOS modules and nothing else. There are no hosts here, no
secrets and no personal data. You import `nixosModules.full` or
`nixosModules.default` into your own configuration, set `othrys.*` options, and
every module stays inert until you enable it.

Modules curate capability and leave the opinions as options. The Hyprland module
knows how to float Steam dialogs and pin windows to workspaces, while you decide
the chords. The router module knows how to build a default-drop nftables ruleset
with NAT and an NFQUEUE hook, while you name the interfaces and subnets.

## Quick start

```bash
mkdir myhost && cd myhost
nix flake init -t github:bippsoft/othrys.nix
```

The template is a minimal host with a managed user, so it imports
`nixosModules.default`, `nixosModules.home` and the Home Manager module, and
has the mandatory options in place. A check instantiates it against this flake on every change,
so it always evaluates. Replace `hardware.nix`, set the user and `stateVersion`
in `configuration.nix`, and build with `nixos-rebuild build --flake .#myhost`.

A host that wants everything imports `nixosModules.full`. It is the module tree
with Home Manager, Stylix, disko, sops-nix and impermanence wired in, each from
this flake's own lock, so the flake declares no input beside othrys and nixpkgs.
Written out by hand, with a desktop enabled:

```nix
{
  inputs = {
    othrys.url = "github:bippsoft/othrys.nix";
    nixpkgs.follows = "othrys/nixpkgs";
  };

  outputs = inputs: {
    nixosConfigurations.myhost = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        # The module tree, the five optional exports and the upstream module
        # each one configures. Import none of those upstream modules beside it.
        inputs.othrys.nixosModules.full

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

A server with no managed user imports `nixosModules.default` and nothing else.
`default` writes into no option of an upstream flake, so the module list is one
line beside the host's own files:

```nix
modules = [
  inputs.othrys.nixosModules.default
  {
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
    othrys.services.ssh = {
      enable = true;
      server.enable = true;
    };
  }
];
```

A host between the two imports `default` and the exports it wants, each beside
its upstream module, as the table under Forewarnings lists them.

`inputs` reaches the modules through `specialArgs`, and two names are read from
it. `inputs.nixpkgs` pins the flake registry to the revision the host is built
from, and `inputs.secrets` is read if you declare one. ashell, Hyprland, nixvim
and nix-index-database come from this flake's own lock, so the example enables
Hyprland without declaring a `hyprland` input. To use another build, set the
module's `package` option, or make this flake's input follow yours with
`inputs.othrys.inputs.hyprland.follows = "hyprland"`.

Two options in that example are mandatory and have no defaults, and the
remaining `othrys.*` lines are the host saying what it wants. Passwords arrive
as a runtime path from a secrets provider rather than as a string, since a
string in a module is a string in the world-readable Nix store. To bring a host
up before its provider decrypts anything, set `initialHashedPassword` to a
`mkpasswd -m yescrypt` hash and move to `passwordFile` afterwards.

## Forewarnings

Six properties of this library surprise first-time consumers. Each one fails
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
trips NixOS's user assertions on a headless host. Modules write Home Manager
configuration and persistent paths to two registries, and one export per
registry applies the guard.

**No upstream module import is required.** `nixosModules.default` writes into no
option namespace owned by another flake, since writing to an undeclared
namespace fails evaluation regardless of `mkIf`. A host built from `default`
alone imports nothing else.

**Home Manager, Stylix, disko, sops-nix and impermanence are optional.** Each
has one othrys module that writes into its namespace, and that module is a
separate export `default` leaves out. A host imports the export and the upstream
module together, and every other host imports neither. `nixosModules.full` is
`default` with all five exports and all five upstream modules, taken from this
flake's lock. A host that imports it imports none of the upstream modules
itself, and picks another revision of one with
`inputs.othrys.inputs.<name>.follows`.

| Wanted | othrys export | Upstream module |
|---|---|---|
| A user Home Manager manages, `othrys.system.users` | `nixosModules.home` | `inputs.home-manager.nixosModules.home-manager` |
| Stylix theming | `nixosModules.stylix` | `inputs.stylix.nixosModules.stylix` |
| The LUKS and BTRFS disk layout, `othrys.system.disko` | `nixosModules.disko` | `inputs.disko.nixosModules.disko` |
| The sops-nix plumbing, `othrys.system.secrets` | `nixosModules.secrets` | `inputs.sops-nix.nixosModules.sops` |
| An ephemeral root, `othrys.system.impermanence` | `nixosModules.impermanence` | `inputs.impermanence.nixosModules.impermanence` |

Enabling `othrys.system.impermanence` without its export fails an assertion that
names it, and so does enabling `othrys.system.users` without
`nixosModules.home` while `othrys.system.users.homeManager.enable` is left on.
A host that wants the account and no Home Manager turns that option off. Every
module that configures the user is then skipped, and one warning names them. Impermanence does not need the disko layout. It wipes the btrfs filesystem on
`othrys.system.impermanence.device`, which the disko export fills and a host
that partitions another way sets itself.

**Enabling a module configures the capability, not the machine.** Anything
identity-shaped, meaning disk IDs, interface names, domains, monitor descriptors
and keys, ships null or neutral and arrives from your configuration.

**`x86_64-linux` is the tested platform.** Every check runs there. For
`aarch64-linux` CI evaluates the server, headless and default host fixtures on
an ARM runner, which shows the module tree evaluates and nothing more. No VM
test runs on ARM and no ARM host has been booted. A module whose package
nixpkgs does not ship for the platform, such as Discord or Plexamp, fails an
assertion that names it.

**An input named `secrets` is read if you declare one.** othrys declares no such
input. When your flake does and imports `nixosModules.secrets`,
`othrys.system.secrets.secretFiles` reads
`inputs.secrets.secretFiles`, which must be an attrset of names to encrypted
sops files such as `{ common = ./common.yaml; }`. Declaring no `secrets` input
is entirely fine and leaves the option empty. Declaring one that does not match
that shape fails at evaluation rather than resolving to an empty attrset, since
a typo'd input name used to surface much later as a missing sops file.

## What is in here

| Namespace | Covers |
|---|---|
| `othrys.system.*` | Identity, locale, Nix settings, kernel, systemd-networkd, bootloader, [disko](https://github.com/nix-community/disko) with LUKS and BTRFS, [impermanence](https://github.com/nix-community/impermanence), persistence, [sops-nix](https://github.com/Mic92/sops-nix) secrets, git, shells, unattended upgrades |
| `othrys.theme.*` | One base16 palette, fonts, opacity and wallpaper that every module reads, with named schemes a host can extend and an optional [Stylix](https://github.com/nix-community/stylix) adapter |
| `othrys.desktop.*` | [Hyprland](https://hyprland.org) through [UWSM](https://github.com/Vladimir-csp/uwsm), [niri](https://github.com/YaLTeR/niri), the [ashell](https://github.com/MalpenZibo/ashell) status bar, the [Vicinae](https://github.com/vicinaehq/vicinae) launcher, greetd login, a Secret Service keyring, idle policy, night light |
| `othrys.hardware.*` | CPU microcode and firmware, NVIDIA with PRIME offload and shader-cache tuning, PipeWire audio, WiFi and Bluetooth, laptop profiles, USB, webcam, pen tablets, ntsync, SMART, UPS, scanners |
| `othrys.services.*` | Router stack (nftables router and NAT, [Suricata](https://suricata.io) IDS/IPS, Kea DHCP, Unbound DNS), CrowdSec, fail2ban, SSH, Tailscale and Headscale, WireGuard, DDNS, VictoriaMetrics, VictoriaLogs, Grafana, vmalert, ntfy, restic, Traefik, Docker, Podman, k3s, mounts, printing |
| `othrys.apps.*` | [Nixvim](https://github.com/nix-community/nixvim), VSCodium, IntelliJ IDEA, Floorp, Ghostty, Kitty, yazi, gh, Claude Code and MCP servers, media apps, Steam with GameMode and MangoHud |

Every option is published in the [generated reference](https://bippsoft.github.io/othrys.nix/reference/options.html),
built from the module tree so it cannot drift.

Infrastructure modules are also exported individually, so
`inputs.othrys.nixosModules.tailscale` works if you want one without the tree,
and a check holds the export list to the module tree. An individual module reads
options that `nixosModules.system` declares, among them the primary user and the
persist root, so import that beside it, and `nixosModules.desktop` beside a
desktop or hardware module. App modules are reachable only through `default`.
`nixosModules.home`, `nixosModules.stylix`, `nixosModules.disko`,
`nixosModules.secrets` and `nixosModules.impermanence` are the five exports
neither `default` nor a group imports.

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
- **`othrys.system.impermanence.persistRoot`** is where everything the modules
  declare as persistent is bound from. Move it and the whole tree follows.

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

CI runs two tiers on every pull request and on every push to `main`. The core
tier covers lint, the secret scan, the docs build, the host and module
evaluations, and the impermanence VM test. The extended tier adds whole-tree
evaluation, the enable-with-defaults matrix, and runtime VM tests for the
router, CrowdSec, restic, Headscale, auto-upgrade, an impermanence reboot and a
full integration host. Branch protection requires one status from each tier,
`Core checks` and `Extended verdict`, and the verdict passes only when every
extended check succeeded.

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
[nix-index-database](https://github.com/nix-community/nix-index-database),
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
