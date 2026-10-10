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
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.{category}.{name} = {
    enable = lib.mkEnableOption "Description of the module";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
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

There is no `username` module argument. Read the primary user from
`config.othrys.system.user.name`, and put every per-user write behind a guard,
since the option has no default and a headless host can leave it unset.

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

Persistence has two forms. A per-user entry is an account write, since
impermanence reads the account's home directory to place it, so the template
guards it on `impermanenceEnabled && usersEnabled`. A system path needs no
account and carries `impermanenceEnabled` alone, as in
`modules/services/traefik.nix`.

```nix
environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
  directories = [
    "/var/lib/{service}"
  ];
};
```

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
