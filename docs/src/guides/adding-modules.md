# Adding Modules

How to create a new NixOS module in this repository.

## Steps

### 1. Create the Module File

Modules live at `modules/{category}/{name}.nix`, where the category is one of
`system`, `desktop`, `hardware`, `services` or `apps`. Application modules sit
one level further down, under `modules/apps/cli/` or `modules/apps/gui/`.

### 2. Define Options and Config

```nix
# modules/{category}/{name}.nix
# One line saying what this module is for
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.{category}.{name};
in {
  options.othrys.{category}.{name} = {
    enable = lib.mkEnableOption "Description of the module";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.persist."{category}.{name}" = {
      user.directories = [
        ".config/{name}"
      ];
    };

    othrys.internal.homeConfig."{category}.{name}" = {
      home.packages = with pkgs; [package-name];
    };
  };
}
```

This is the template in `CONTRIBUTING.md`, and `modules/apps/cli/gh.nix` is a
module that follows it.

There is no `username` module argument. A module that needs the primary user
reads `config.othrys.system.user.name`, and puts every account write behind a
guard on `othrys.system.users.enable`, since the option has no default and a
headless host can leave it unset. The template needs neither, because both of
its per-user writes go through a registry.

User configuration goes into `othrys.internal.homeConfig`, under a key that is
the module's own option path. `modules/system/users.nix` splices every entry
into `home-manager.users.<name>` behind `othrys.system.users.homeManaged`, so
the module spells no Home Manager guard of its own. A module never writes
`home-manager.users` directly, and the `contract-guards` hook rejects one that
does. A module whose user configuration depends on a second option wraps the
whole entry in a top-level `lib.mkIf`, as `modules/services/docs.nix` does.

```nix
othrys.internal.homeConfig."services.docs" = lib.mkIf cfg.desktopEntry {
  # User-level configuration
};
```

Persistent paths go into `othrys.internal.persist`, under the same key. Paths
in the primary user's home go under `user`, relative to it, and a system path
goes in `directories` or `files`, as in `modules/services/traefik.nix`.

```nix
othrys.internal.persist."services.{service}" = {
  directories = [
    "/var/lib/{service}"
  ];
};
```

The module spells no guard here either. `modules/system/impermanence.nix`,
exported as `nixosModules.impermanence`, splices the registry into
`environment.persistence` when impermanence is on, and leaves the paths under
`user` out on a host with no managed account. A module never writes
`environment.persistence` directly. That option exists only on a host that
imports the impermanence module, so a direct write fails on every other host,
and the `contract-guards` hook rejects it.

### 3. Import in Category default.nix

Add the import to `modules/{category}/default.nix`:

```nix
imports = [
  ./{name}.nix
  # ... other modules
];
```

### 4. Enable in the Consuming Flake

Modules stay inert until a consuming flake turns them on. Where the enable goes
is that flake's business, whether in a shared profile imported by several hosts
or in one host's own configuration:

```nix
# e.g. hosts/<hostname>/default.nix in your flake
othrys.{category}.{name}.enable = true;
```

### 5. Test

```bash
just check
```

That is the whole of what this repository can verify, since it holds no hosts.
Building an actual machine happens in the flake that consumes this one, against
its own host definitions.

## Conventions

{{#include ../../../CONTRIBUTING.md:comment-conventions}}
