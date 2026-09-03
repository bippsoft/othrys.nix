# Contributing

Guide for adding modules, fixing issues and maintaining this library.

## Consumer Contract

Four properties hold across every module here, and changing any of them breaks
consuming flakes. `flake/checks/` encodes all four, so a violation fails
evaluation rather than waiting to surprise somebody.

<!-- ANCHOR: consumer-contract -->

1. **No `username` module argument.** Read the primary user from
   `config.othrys.system.user.name`. The option has no default.
1. **Guard every per-user write.** Account writes behind
   `othrys.system.users.enable`, Home Manager writes behind
   `othrys.system.users.homeManaged`, both at the attrset level, never on a leaf.
1. **`nixosModules.default` writes into upstream namespaces.** Consumers must
   also import `home-manager`, `disko`, `stylix`, `sops-nix` and `impermanence`,
   even when the matching othrys feature is off.
1. **specialArgs carry `inputs` only.** Not `username`, not `hostname`.

<!-- ANCHOR_END: consumer-contract -->

The reasoning behind each, which the mirrored copies leave out:

**The user is an option because a module argument is invisible.** A `username`
specialArg is a coupling nothing declares and nothing checks, so a module can
read it without any consumer knowing the module needs it. An option appears in
the generated reference, fails loudly when unset, and can be read lazily, which
is what lets a headless host omit it entirely.

**The guards wrap attrsets because a leaf-level `mkIf` is not a guard.** Writing
`home-manager.users.<name>.foo = lib.mkIf cond bar` still materializes
`home-manager.users.<name>`, which makes Home Manager reference the user's home
directory and trips NixOS's own user assertions on a host with no such account.
The condition has to sit above the attribute path, not inside it. Account
creation and environment management are also separate concerns, which is why
there are two guards rather than one: a server may want a login account without
Home Manager owning its dotfiles.

**The upstream imports are unconditional because `mkIf` does not defer option
existence.** Writing into an undeclared option namespace fails at evaluation
whether or not the write is conditional, so importing home-manager only when a
Home Manager feature is enabled does not work. Consumers import all five.

**specialArgs stay minimal because they are the one part of the interface the
module system cannot type.** Every additional specialArg is an undeclared
requirement a consumer discovers by hitting an error.

## Module Pattern

All modules follow the `othrys.*` namespace convention:

1. Create `modules/{category}/{name}.nix`
1. Define options under `options.othrys.{category}.{name}`
1. Use `lib.mkEnableOption` for the main toggle
1. Guard all config with `config = lib.mkIf cfg.enable { ... };`
1. Import in `modules/{category}/default.nix`
1. Enable in a host config with `othrys.{category}.{name}.enable = true;`

### Module Template

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
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.{category}.{name} = {
    enable = lib.mkEnableOption "Description";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
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

There is no `username` module argument. The primary user comes from
`config.othrys.system.user.name`, and that option has no default, so reading it
on a host that never set it is a hard evaluation error. Any write that touches a
per-user path must therefore sit behind a guard.

Two guards exist, and they are not interchangeable. Account-level writes
(`users.users.<name>`, `/persist` home directories, wipe-script home recreation)
go behind `othrys.system.users.enable`, spelled in the module. Home Manager
writes do not spell a guard at all. A module contributes to
`othrys.internal.homeConfig`, keyed by its own option path, and
`modules/system/users.nix` splices the whole registry into
`home-manager.users.<name>` behind `othrys.system.users.homeManaged`. Nothing
else in `modules/` may write `home-manager.users`, and `contract-guards` in
`flake/checks/` enforces that as a prohibition.

The registry exists because the guard belongs at the attrset level rather than
on a leaf. A leaf-level `mkIf` still materializes the Home Manager user and
trips the NixOS user assertions on a headless host, and that distinction is easy
to get wrong once per module and impossible to get wrong in one place. It also
gives the diagnostic somewhere to live, since `users.nix` warns once naming every
module whose user configuration was skipped rather than each module warning
separately on every rebuild.

Three details follow from the registry:

- A module with a second condition wraps its own value, as
  `othrys.internal.homeConfig."services.docs" = lib.mkIf cfg.desktopEntry { ... };`.
  A false condition drops the key, so nothing is written and nothing is reported.
- The option is `lib.types.raw`, so `lib.mkForce` and `lib.mkDefault` inside a
  contribution survive to `home-manager.users` and still win or lose against
  upstream definitions. An ordinary type would discharge them at the registry
  and silently change what a module means.
- Reading evaluated Home Manager output is not a write.
  `modules/apps/gui/vscode/default.nix` reads
  `config.home-manager.users.<name>.programs.nixvim.build.package`, and the
  `config.` prefix is what distinguishes a read from a write.

The `eval-host-server`, `eval-host-anonymous`, `eval-host-server-account`,
`eval-host-app-no-hm` and `eval-host-app-no-hm-full` checks in `flake/checks/`
encode all of this.

## Comments and Anchors

<!-- ANCHOR: comment-conventions -->

Comments here earn their place or they get deleted. Four kinds are load-bearing.

**File header.** Every `.nix` file under `modules/` and `flake/` opens with two
lines, the repository-relative path and a one-line statement of purpose. The path
line matters because these files are read as `{{#include}}` fragments in the
documentation, stripped of their filename.

```nix
# modules/services/example.nix
# What this module is for, in one line
```

**Anchor markers.** `# ANCHOR: <name>` and `# ANCHOR_END: <name>` mark the regions
that documentation pages embed. Naming follows two rules. An options block
anchors as `<basename>-options`. A config excerpt anchors as `<basename>-<what>`
with a suffix describing what the excerpt shows, as in `disko-partitions` or
`hyprland-keybindings`.

Add an anchor only when a documentation page actually embeds it. Every option is
already published in `docs/src/reference/options.md`, generated from the module
tree, so an anchor that no page includes is duplication with a maintenance cost
and nothing reading it. The `comment-hygiene` check fails on one.

**Rationale.** Comments that answer why, never what. A guard that has to sit at
the attrset level, an assertion that needs its own `mkIf`, an upstream defect and
the check that guards against its return. These are the comments worth writing at
length, since they carry knowledge the code cannot.

**Attribution.** Where a module is adapted from another project, say so and name
it.

Everything else goes. No banner rules, no `# ====` separators and no boxed
headers. No comment that restates the line beneath it. No `NOTE:`, `TODO:` or
`FIXME:` prefixes. No em dashes anywhere, in comments or in prose.

Section labels inside long literal configuration blocks are the exception that
survives, since a `# Cursor` label over five cursor settings in a hundred-line
terminal config is navigation rather than restatement.

<!-- ANCHOR_END: comment-conventions -->

## Package Placement

Packages go in one of two places. Choose by who needs the binary, not by
convenience.

`home-manager.users.${username}.home.packages` is the default. User-facing
applications and CLI tools live here (browsers, editors, `gh`, `yazi`, language
toolchains). They are scoped to the user and pair naturally with the program's
Home Manager configuration.

`environment.systemPackages` is reserved for packages that must exist outside the
user session. That covers system and Nix infrastructure needed in root or sudo
contexts, such as the formatters, linters and rebuild helpers (`alejandra`,
`statix`, `deadnix`, `nvd`, `nix-output-monitor`, `nh`) used by `sudo nixos-rebuild`, `nh os switch` and CI (see `modules/apps/cli/development.nix`).
It also covers packages that must load into a system layer, such as the MangoHud
Vulkan and GL overlay in `modules/apps/gui/gaming/mangohud.nix`, which the
graphics stack injects globally even though its config lives in Home Manager.

When a module needs both a system binary and per-user config, split it. The
package goes in `environment.systemPackages` and the `programs.<name>` settings
go in `home-manager.users.${username}`, as MangoHud does.

## Impermanence

All persistent state must be declared explicitly. If a module stores state on
disk, declare the persistence in that module rather than in `persistence.nix`.

```nix
environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
  users.${username}.directories = [
    ".config/{app}"
    ".local/share/{app}"
  ];
};
```

## Documentation

Module pages live under `docs/src/modules/`. A page argues about a subsystem and
names the gotchas that reading the source will not reveal, then embeds the option
surface through an anchor under an `### Options` heading. The generated reference
in `docs/src/reference/options.md` serves the other reader, the one looking up a
single option by name, and is never edited by hand.

## Testing

```bash
just check            # Flake checks (eval, pre-commit hooks, VM tests)
just lint             # Format check, statix, deadnix
just ci               # lint plus flake check
```

Changes that affect real systems are validated from a consuming fleet repository
with `just build <hostname>`, `just diff <hostname>` and `just test <hostname>`.

## Linting

Four checks run automatically through pre-commit hooks.

- **treefmt** formats Nix, shell, TOML, YAML and Markdown (`just fmt`)
- **Statix** lints Nix
- **Deadnix** finds dead code
- **comment-hygiene** enforces the conventions above

## Commit Conventions

- Use imperative mood, so "Add kitty module" rather than "Added kitty module"
- Reference the module category where it applies
- Keep the first line under 72 characters

## Secrets

This repository holds no secrets, and its flake has no `secrets` input. Modules
accept runtime file paths (`passwordFile`, `clientSecretFile` and similar), and
the consuming flake decides what provides them. Never commit a plaintext secret,
and never accept an option design that puts one in the Nix store.

## AI Usage

Contributions made with AI assistance are subject to [AI_POLICY.md](AI_POLICY.md).
