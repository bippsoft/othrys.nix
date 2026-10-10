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

Home Manager is loaded as a NixOS module and manages one user, the primary user
named by `othrys.system.user.name`. A module does not write
`home-manager.users` itself. It contributes an attribute set to the
`othrys.internal.homeConfig` registry, under a key that is its own option path.

```nix
othrys.internal.homeConfig."apps.gh" = {
  programs.gh.enable = true;
};
```

`modules/system/users.nix` merges every entry into `home-manager.users.<name>`
behind `othrys.system.users.homeManaged`. The guard sits at the attrset level
in that one place, so a headless host never materializes a Home Manager user.
A leaf-level `mkIf` in each module would still create the user. On a host
without a managed user the same module warns once and names every module whose
entry was skipped.

A module with a condition of its own wraps the whole entry in a top-level
`lib.mkIf`, as `modules/services/docs.nix` does. A false condition drops the
key from the registry.

```nix
othrys.internal.homeConfig."services.docs" = lib.mkIf cfg.desktopEntry {
  # User-level configuration here
};
```

Account-level writes, such as group memberships in
`users.users.${username}.extraGroups`, stay in the module and are guarded on
`othrys.system.users.enable` at the attrset level. `CONTRIBUTING.md` carries
the full reasoning, and the `contract-guards` hook rejects a module that writes
`home-manager.users`.

## Impermanence Pattern

Modules that store persistent state declare their own persistence. A per-user
entry carries the users guard beside the impermanence one, since impermanence
reads the account's home directory to place the bind mount.

```nix
environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
  users.${username}.directories = [
    ".config/{app}"
  ];
};
```

A system path needs no account and carries the impermanence guard alone.

```nix
environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
  directories = [
    "/var/lib/{service}"
  ];
};
```

`persistRoot` is `config.othrys.system.impermanence.persistRoot`.
