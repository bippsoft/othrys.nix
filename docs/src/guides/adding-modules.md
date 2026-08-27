# Adding Modules

How to create a new NixOS module in this repository.

## Steps

### 1. Create the Module File

Modules live at `modules/{category}/{name}.nix`, where the category is one of
`system`, `desktop`, `hardware`, `services` or `apps`.

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
  hmEnabled = config.othrys.system.users.homeManaged;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.{category}.{name} = {
    enable = lib.mkEnableOption "Description of the module";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [package-name];

    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/{name}"
      ];
    };

    home-manager.users = lib.mkIf hmEnabled {
      ${username} = {
        # User-level configuration
      };
    };
  };
}
```

There is no `username` module argument. Read the primary user from
`config.othrys.system.user.name`, and put every per-user write behind a guard,
since the option has no default and a headless host may never set it. Account
writes use `othrys.system.users.enable`, Home Manager writes use
`othrys.system.users.homeManaged`, and both guards belong at the attrset level
rather than on a leaf.

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
