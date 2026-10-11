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

Five files are left out of their category, since each writes into an option namespace that only an upstream flake's module declares. `modules/system/home.nix`, `modules/theme/stylix.nix`, `modules/system/disko.nix`, `modules/system/secrets.nix` and `modules/system/impermanence.nix` are exported as `nixosModules.home`, `nixosModules.stylix`, `nixosModules.disko`, `nixosModules.secrets` and `nixosModules.impermanence`, and a host imports each together with the upstream module it configures. `nixosModules.full` aggregates `default`, the five and their upstream modules. See [Host Configuration](./host-configuration.md).

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

`modules/system/users.nix` declares the registry, and `modules/system/home.nix`
merges every entry into `home-manager.users.<name>` behind
`othrys.system.users.homeManaged`.

```nix
{{#include ../../../modules/system/home.nix:home-splice}}
```

The guard sits at the attrset level in that one place, so a headless host never
materializes a Home Manager user. A leaf-level `mkIf` in each module would
still create the user.

`home.nix` is exported as `nixosModules.home` and is not part of
`nixosModules.default`, so the tree evaluates on a host that imports no Home
Manager module. `homeManaged` is true when the account exists,
`othrys.system.users.homeManager.enable` is on and the export is imported. On
any other host `users.nix` warns once and names every module whose entry was
skipped. A host with the account and `homeManager.enable` left on fails an
assertion that names the export, since most modules that configure the user
write nothing else.

A module does not read `config.home-manager` either, for the same reason it
does not write it. A value one Home Manager module needs from another is read
inside the user's configuration, as `modules/apps/gui/vscode/default.nix` does
for the neovim that nixvim builds.

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
the full reasoning, and the `contract-guards` hook rejects a module that names
`home-manager.users` or `environment.persistence`.

## Impermanence Pattern

Modules that store persistent state declare their own persistence, in a second
registry, `othrys.internal.persist`, under the same key as the Home Manager one.
A path in the primary user's home goes under `user`, relative to the home.

```nix
othrys.internal.persist."apps.{app}" = {
  user.directories = [
    ".config/{app}"
  ];
};
```

A system path goes in `directories` or `files`.

```nix
othrys.internal.persist."services.{service}" = {
  directories = [
    "/var/lib/{service}"
  ];
};
```

Neither form spells a guard. `modules/system/impermanence.nix` reads the
registry and writes it into `environment.persistence` under
`config.othrys.system.impermanence.persistRoot`. It writes the system paths
when impermanence is on, and the paths under `user` only when
`othrys.system.users.enable` is on as well, since impermanence reads the
account's home directory to place the bind mount.

That file is exported as `nixosModules.impermanence` and is not part of
`nixosModules.default`, so the tree evaluates on a host that imports no
impermanence module. See [Impermanence](../system/impermanence.md).
