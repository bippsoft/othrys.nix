# Module System

All custom options use the `othrys.*` namespace (e.g., `othrys.desktop.login.enable`). Each module follows a consistent pattern.

## Standard Module Structure

A module declares options under `options.othrys.{category}.{name}`, guards config with `lib.mkIf cfg.enable`, and integrates with Home Manager and impermanence as needed.

### Example: Login Manager (greetd)

**Options:**

```nix
{{#include ../../../modules/desktop/login.nix:login-options}}
```

**Config:**

```nix
{{#include ../../../modules/desktop/login.nix:login-config}}
```

## Category Organization

Each `modules/{category}/default.nix` imports all modules in that category, and `nixosModules.default` aggregates every category. A consuming flake that imports `nixosModules.default` pulls in every module, but nothing activates until `othrys.{category}.{name}.enable = true` is set in the consumer's configuration.

## Home Manager Integration

Home Manager is loaded as a NixOS module (not standalone). Modules configure
user-level settings for the primary user (`othrys.system.user.name`), guarded
at the attrset level by `othrys.system.users.enable` so headless hosts never
materialize a home-manager user (a leaf-level `mkIf` is not enough, since the user
would still be created):

```nix
home-manager.users = lib.mkIf config.othrys.system.users.enable {
  ${username} = {
    # User-level configuration here
  };
};
```

The same guard applies to any other per-user write, such as group memberships
(`users.users.${username}.extraGroups`).

## Impermanence Pattern

Modules that store persistent state declare their own persistence. Per-user
directories carry the users guard as well:

```nix
environment.persistence."/persist" = lib.mkIf (impermanenceEnabled && usersEnabled) {
  users.${username}.directories = [
    ".config/{app}"
  ];
};
```
