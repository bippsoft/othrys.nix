# Host Configuration

Hosts compose modules by setting `othrys.*` options. Host configurations do not live in this repository. They belong to a private fleet flake that consumes othrys.nix as an input. This page documents the contract a consuming flake must satisfy and sketches what a host looks like.

## Consuming the Module Library

`nix flake init -t github:<owner>/othrys.nix` writes a minimal consuming flake
with everything below already in place. The `eval-template` check instantiates
that template with only the inputs a consumer has, so it cannot drift from the
contract described here.

A fleet flake takes othrys.nix as an input and builds hosts with `nixosSystem`. `nixosModules.default` is the module tree, and it writes into no option namespace of another flake, so a host built from it alone imports nothing else. Five exports sit outside it, each of which hands part of the tree to an upstream module, and `nixosModules.full` is `default` with all five and the five upstream modules.

A host that wants everything imports the aggregate. The upstream modules come from the lock of othrys, so the fleet flake declares no input for them:

```nix
# fleet flake.nix (illustrative)
inputs = {
  othrys.url = "github:<owner>/othrys.nix";
  nixpkgs.follows = "othrys/nixpkgs";
};
```

```nix
# mkHost (illustrative)
inputs.nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {inherit inputs;};
  modules = [
    ./hosts/${hostname}

    # The tree, the five exports and the five upstream modules.
    inputs.othrys.nixosModules.full
  ];
}
```

A host that imports `full` imports none of the five upstream modules itself, since two revisions of one module declare every option twice. A fleet that wants its own revision of one makes the input of othrys follow it, as in `inputs.othrys.inputs.home-manager.follows = "home-manager"`, and every host then gets that revision through `full`.

A server with no managed user imports `default` alone:

```nix
modules = [
  ./hosts/${hostname}
  inputs.othrys.nixosModules.default
];
```

A host between the two imports `default` and the exports it wants, each beside the upstream module it configures. The fleet flake then declares those inputs, typically following othrys so hosts build against the versions the library is locked and tested with:

```nix
# fleet flake.nix (illustrative)
inputs = {
  othrys.url = "github:<owner>/othrys.nix";
  nixpkgs.follows = "othrys/nixpkgs";

  # One for each export a host imports.
  home-manager.follows = "othrys/home-manager";
  impermanence.follows = "othrys/impermanence";
  disko.follows = "othrys/disko";
  sops-nix.follows = "othrys/sops-nix";
  stylix.follows = "othrys/stylix";
};
```

```nix
# the host's module list (illustrative)
modules = [
  ./hosts/${hostname}

  inputs.othrys.nixosModules.default

  # Each othrys export beside the upstream module it configures.
  inputs.othrys.nixosModules.home
  inputs.home-manager.nixosModules.home-manager
  inputs.othrys.nixosModules.impermanence
  inputs.impermanence.nixosModules.impermanence
  inputs.othrys.nixosModules.disko
  inputs.disko.nixosModules.disko
  inputs.othrys.nixosModules.secrets
  inputs.sops-nix.nixosModules.sops
  inputs.othrys.nixosModules.stylix
  inputs.stylix.nixosModules.stylix
];
```

| Export | Upstream module | Needed by |
|--------|-----------------|-----------|
| `nixosModules.home` | `inputs.home-manager.nixosModules.home-manager` | A host whose primary user Home Manager manages |
| `nixosModules.impermanence` | `inputs.impermanence.nixosModules.impermanence` | A host with an ephemeral root |
| `nixosModules.disko` | `inputs.disko.nixosModules.disko` | A host that wants the othrys disk layout |
| `nixosModules.secrets` | `inputs.sops-nix.nixosModules.sops` | A host that wants the othrys sops-nix plumbing |
| `nixosModules.stylix` | `inputs.stylix.nixosModules.stylix` | A host that wants Stylix |

Home Manager is needed only on a host with a managed user. Every module names its user configuration in `othrys.internal.homeConfig`, an option `nixosModules.default` declares itself, and `modules/system/home.nix` is the only file that writes into the `home-manager` namespace. It is the separate export `nixosModules.home`, which a host imports together with `inputs.home-manager.nixosModules.home-manager`. It hands the registry to `home-manager.users.<name>`, and while `othrys.system.nix` is on it sets `home-manager.useGlobalPkgs` and `home-manager.useUserPackages` as defaults, so the user's packages follow the system's nixpkgs policy. A host that enables `othrys.system.users` and leaves `othrys.system.users.homeManager.enable` on without the export fails an assertion that names it. See [User Identity and Headless Hosts](#user-identity-and-headless-hosts).

impermanence is needed only on a host with an ephemeral root. Every module names what it persists in `othrys.internal.persist`, an option `nixosModules.default` declares itself, and `modules/system/impermanence.nix` is the only file that writes into `environment.persistence`. It is the separate export `nixosModules.impermanence`, which a host imports together with `inputs.impermanence.nixosModules.impermanence`. A host with a persistent root imports neither. A host that sets `othrys.system.impermanence.enable` without the export fails an assertion that names it. See [Impermanence](../system/impermanence.md).

disko is needed only on a host that wants the othrys disk layout. `modules/system/disko.nix` is the only file that writes into the `disko` namespace, and it is the separate export `nixosModules.disko`, which a host imports together with `inputs.disko.nixosModules.disko`. A host that partitions another way imports neither and, if it enables impermanence, sets `othrys.system.impermanence.device` itself. See [Disko](../system/disko.md) and [Impermanence](../system/impermanence.md).

sops-nix is needed only on a host that wants the othrys secrets plumbing. `modules/system/secrets.nix` is the only file that writes into the `sops` namespace, and it is the separate export `nixosModules.secrets`, which a host imports together with `inputs.sops-nix.nixosModules.sops`. Every other module takes a secret as a runtime file path, so a host with another provider imports neither. See [Secrets Management](../system/secrets.md).

Stylix is needed only on a host that wants it. Nothing in `nixosModules.default` writes into the `stylix` namespace, since every module reads its colours and fonts from `othrys.theme`. The adapter that configures Stylix from the theme is the separate export `nixosModules.stylix`, and a host imports it together with `inputs.stylix.nixosModules.stylix`. A host that imports neither evaluates the same without them. See [Theming](../guides/theming.md).

Lanzaboote is needed only for Secure Boot on `systemd-boot`, where the host adds a `lanzaboote` input and imports `inputs.lanzaboote.nixosModules.lanzaboote`. Every other host leaves it out and evaluates the same without it. See [Bootloader & Secure Boot](../system/bootloader.md).

## Re-exporting the Dev Shell

A consuming flake that wants the same tools and commit hooks re-exports
`devShells.consumer`, not `devShells.default`:

```nix
devShells.default = inputs'.othrys.devShells.consumer;
```

Both shells carry the same packages. `consumer` installs the hooks that suit any
Nix repository, which are `treefmt`, `statix`, `deadnix`, `commitizen` and
`gitleaks`. `default` adds `comment-hygiene`, `contract-mirror` and
`contract-guards`, which read this repository's own tree and reject any other.

## The specialArgs Contract

othrys modules read one argument from `specialArgs`, and a host may leave it out:

| Argument | Type | Used for |
|----------|------|----------|
| `inputs` | attrset | The two names in the table below, each read with a fallback |

| Input | Read by | Without it |
|-------|---------|------------|
| `nixpkgs` | `othrys.system.nix`, which pins the flake registry and `NIX_PATH` to it and turns channels off | NixOS pins the registry and `NIX_PATH` to the source `nixpkgs.lib.nixosSystem` was called from, without the revision and hash, and channels stay as NixOS sets them |
| `secrets` | `othrys.system.secrets`, as the default of `secretFiles` when the input exists | `secretFiles` defaults to an empty set |

Both stay with the consumer because they are the consumer's by nature. The
registry pin has to name the revision the host is built from, and the secrets
are the consumer's own data. No Home Manager module here reads `inputs`, so
`home-manager.extraSpecialArgs` is needed only by a fleet's own modules.

Every other flake comes from this flake's own lock. `nixosModules.default`
hands `ashell`, `hyprland`, `nixvim` and `nix-index-database` to the modules as
the `othrysInputs` module argument, and imports niri-flake's module directly. A
consuming flake declares none of them, and an input of one of those names is
not read. [Flake Inputs](./flake-inputs.md#what-a-consumer-declares) describes
how a consumer substitutes its own.

| Locked input | Module | Override |
|--------------|--------|----------|
| `hyprland` | `othrys.desktop.compositors.hyprland` | `package` and `portalPackage` |
| `ashell` | `othrys.desktop.ashell` | `package` |
| `nixvim` | `othrys.apps.nixvim` | `inputs.othrys.inputs.nixvim.follows` |
| `nix-index-database` | `othrys.apps.comma` | `inputs.othrys.inputs.nix-index-database.follows` |

The individual exports `nixosModules.hyprland`, `ashell`, `nix`, `secrets`,
`system` and `desktop` carry the same arguments, so they work without
`default`.

There is no `username` or `hostname` specialArg. The primary user is named via
the `othrys.system.user.name` option, and hosts set `networking.hostName`
directly.

## User Identity and Headless Hosts

`othrys.system.user.name` names the primary user. It is read lazily, only
when a per-user feature is active. Account creation and environment management
are separate toggles, so hosts pick the coupling they want:

- **Workstations** set `user.name`, enable `othrys.system.users`, import
  `nixosModules.home` with the Home Manager module, and get the managed
  account plus all home-manager configuration (`users.homeManager.enable`
  defaults to `true`). `nixosModules.full` holds both imports.
- **Servers with a login account** (an admin user, or an account a webapp runs
  under) enable `othrys.system.users` but set
  `othrys.system.users.homeManager.enable = false`: the account, groups, and
  persisted home exist, and no home-manager state is generated. Such a host
  needs neither the export nor the Home Manager module.
- **Headless/root-only hosts** leave `othrys.system.users` off entirely, or
  even omit `user.name`. Server modules like `ssh`, `docker`, `secrets`, or
  `impermanence` work without a primary user, and the host imports
  `nixosModules.default` alone.

Modules key account-level writes (group memberships, `/persist` home
directories) on `othrys.system.users.enable`. Home Manager configuration goes
to the `othrys.internal.homeConfig` registry, which `nixosModules.home` applies
behind the derived `othrys.system.users.homeManaged` flag. That flag is true
when the account exists, `homeManager.enable` is on and the export is
imported. On any other host the registry entries are skipped and one warning
names the modules they came from. Service accounts for
individual daemons are not othrys's concern. Declare them with plain
`users.users.<name>.isSystemUser` (most NixOS service modules do this
themselves).

The `eval-host-server`, `eval-host-anonymous`, and `eval-host-server-account`
checks in `flake/checks/` enforce this contract in CI, on hosts that import no
Home Manager module, and `eval-optional-exports` reads back each shape above.

Additionally, `nixosModules.default` injects `othrysSelf` (this flake's own source) as a module argument, so modules that build from the flake source, such as the [docs server](../modules/services.md), work without extra wiring. Importing individual module files instead of `default` skips that injection. The argument then does not exist, so set `othrys.services.docs.package` explicitly, or the default fails with the module system's missing-argument error when it is read.

Secrets are the consumer's responsibility. On a host that imports `nixosModules.secrets`, `othrys.system.secrets.secretFiles` defaults to `inputs.secrets.secretFiles` when the consuming flake declares a `secrets` input, which this library does not.

## Anatomy of a Host

A host config should hold only what is true of that machine specifically, meaning hardware facts and role selection. Shared settings belong in profile modules the fleet defines once and imports per host:

```nix
# hosts/example/default.nix (illustrative)
{...}: {
  imports = [
    ./hardware.nix
    ../../profiles/base.nix # identity, shell, secrets, ssh, security
    ../../profiles/desktop.nix # hyprland session, theming, GUI apps
  ];
  networking.hostName = "example";

  othrys.system.disko = {
    enable = true;
    device = "/dev/disk/by-id/<disk-id>";
    swapSize = "16G";
    luks.fido2.enable = true;
  };

  othrys.desktop.compositors.hyprland.monitors = [
    {
      output = "desc:<monitor>";
      mode = "1920x1080@144";
      position = "0x0";
      scale = "1";
    }
  ];

  othrys.hardware.nvidia.enable = true;
}
```

The rule of thumb for what goes where is simple. If you would have to re-discover a value when the disk dies (disk IDs, bus IDs, monitor descriptors), it belongs in the host. If it is true of every machine or of a machine role, it belongs in a profile.
