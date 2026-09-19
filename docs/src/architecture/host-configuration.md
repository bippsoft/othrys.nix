# Host Configuration

Hosts compose modules by setting `othrys.*` options. Host configurations do not live in this repository. They belong to a private fleet flake that consumes othrys.nix as an input. This page documents the contract a consuming flake must satisfy and sketches what a host looks like.

## Consuming the Module Library

`nix flake init -t github:<owner>/othrys.nix` writes a minimal consuming flake
with everything below already in place. The `eval-template` check instantiates
that template with only the inputs a consumer has, so it cannot drift from the
contract described here.

A fleet flake takes othrys.nix as an input and builds hosts with `nixosSystem`, importing `nixosModules.default` (the full module tree) alongside the external modules the library builds on:

```nix
# fleet flake.nix (illustrative)
inputs = {
  othrys.url = "github:<owner>/othrys.nix";

  # Shared dependencies follow othrys so hosts build against exactly the
  # versions the module library is locked and tested to.
  nixpkgs.follows = "othrys/nixpkgs";
  home-manager.follows = "othrys/home-manager";
  hyprland.follows = "othrys/hyprland";
  disko.follows = "othrys/disko";
  impermanence.follows = "othrys/impermanence";
  stylix.follows = "othrys/stylix";
  sops-nix.follows = "othrys/sops-nix";
};
```

```nix
# mkHost (illustrative)
inputs.nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = {inherit inputs;};
  modules = [
    ./hosts/${hostname}

    inputs.othrys.nixosModules.default

    inputs.disko.nixosModules.disko
    inputs.impermanence.nixosModules.impermanence
    inputs.stylix.nixosModules.stylix
    inputs.sops-nix.nixosModules.sops
    inputs.home-manager.nixosModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = {inherit inputs;};
      };
    }
  ];
}
```

The five upstream modules above are required on every host, even when the matching othrys feature is off, because `nixosModules.default` writes into their option namespaces. Lanzaboote is an optional sixth. It is needed only for Secure Boot on `systemd-boot`, where the host adds a `lanzaboote` input and imports `inputs.lanzaboote.nixosModules.lanzaboote`. Every other host leaves it out and evaluates the same without it. See [Bootloader & Secure Boot](../system/bootloader.md).

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

othrys modules expect one argument via `specialArgs` (and `home-manager.extraSpecialArgs`):

| Argument | Type | Used for |
|----------|------|----------|
| `inputs` | attrset | Modules that reference flake inputs directly (e.g. Hyprland uses `inputs.hyprland`); must contain the inputs shown above under these names |

There is no `username` or `hostname` specialArg. The primary user is named via
the `othrys.system.user.name` option, and hosts set `networking.hostName`
directly.

## User Identity and Headless Hosts

`othrys.system.user.name` names the primary user. It is read lazily, only
when a per-user feature is active. Account creation and environment management
are separate toggles, so hosts pick the coupling they want:

- **Workstations** set `user.name`, enable `othrys.system.users`, and get the
  managed account plus all home-manager configuration
  (`users.homeManager.enable` defaults to `true`).
- **Servers with a login account** (an admin user, or an account a webapp runs
  under) enable `othrys.system.users` but set
  `othrys.system.users.homeManager.enable = false`: the account, groups, and
  persisted home exist, and no home-manager state is generated.
- **Headless/root-only hosts** leave `othrys.system.users` off entirely, or
  even omit `user.name`. Server modules like `ssh`, `docker`, `secrets`, or
  `impermanence` work without a primary user.

Modules key account-level writes (group memberships, `/persist` home
directories) on `othrys.system.users.enable` and home-manager writes on the
derived `othrys.system.users.homeManaged` flag. Service accounts for
individual daemons are not othrys's concern. Declare them with plain
`users.users.<name>.isSystemUser` (most NixOS service modules do this
themselves).

The `eval-host-server`, `eval-host-anonymous`, and `eval-host-server-account`
checks in `flake/checks/` enforce this contract in CI.

Additionally, `nixosModules.default` injects `othrysSelf` (this flake's own source) as a module argument, so modules that build from the flake source, such as the [docs server](../modules/services.md), work without extra wiring. Importing individual module files instead of `default` skips that injection; set such modules' package options explicitly if you use them.

Secrets are the consumer's responsibility: `othrys.system.secrets.secretFiles` defaults to `inputs.secrets.secretFiles` when the consuming flake declares a `secrets` input (this library does not).

## Anatomy of a Host

A host config should hold only what is true of that machine specifically, meaning hardware facts and role selection. Shared settings belong in profile modules the fleet defines once and imports per host:

```nix
# hosts/example/default.nix (illustrative)
{hostname, ...}: {
  imports = [
    ./hardware.nix
    ../../profiles/base.nix # identity, shell, secrets, ssh, security
    ../../profiles/desktop.nix # hyprland session, theming, GUI apps
  ];
  networking.hostName = hostname;

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
