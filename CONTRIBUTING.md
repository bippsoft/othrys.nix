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
   `othrys.system.users.enable`, at the attrset level, never on a leaf. Home
   Manager configuration goes to `othrys.internal.homeConfig` and persistent
   paths go to `othrys.internal.persist`, never to `home-manager.users` or
   `environment.persistence`. One export applies each registry and its guard,
   `nixosModules.home` for the first and `nixosModules.impermanence` for the
   second.
1. **`nixosModules.default` writes into no upstream namespace.** A host built
   from it alone imports no other module. Five exports are optional, and a
   host imports each together with the upstream module it configures.
   `nixosModules.home` goes with Home Manager, `nixosModules.stylix` with
   Stylix, `nixosModules.disko` with disko, `nixosModules.secrets` with
   sops-nix and `nixosModules.impermanence` with impermanence.
   `nixosModules.full` is `default` with all five and the five upstream
   modules, taken from this flake's own lock.
1. **specialArgs carry `inputs` or nothing.** Modules read two names from it,
   `nixpkgs` for the registry pin and the optional `secrets`. Not `username`,
   not `hostname`.

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

A persistent path in the user's home is an account-level write as well, since
the impermanence module reads `users.users.<name>.home` to place the bind
mount. No module spells either of these guards for its own configuration. Home
Manager configuration is written to `othrys.internal.homeConfig`, which
`modules/system/home.nix` splices into `home-manager.users` behind
`othrys.system.users.homeManaged`. Persistent paths are written to
`othrys.internal.persist`, which `modules/system/impermanence.nix` splices into
`environment.persistence`, the system paths behind
`othrys.system.impermanence.enable` and the paths under `user` behind
`othrys.system.users.enable` as well. Each guard is written in one file, so no
module can spell it wrongly.

**No upstream import is required because every write into an upstream
namespace lives in an export.** `mkIf` does not defer option existence. Writing
into an undeclared option namespace fails at evaluation whether or not the
write is conditional, so a module in `default` cannot write into the options
of Home Manager, Stylix, disko, sops-nix or impermanence and still evaluate on
a host that imports none of them. Each of the five is therefore reached through
one file that `default` does not import, and the modules in `default` write to
options that `default` declares itself.

Stylix is the first case. Every module in `nixosModules.default` reads its colours and
fonts from `othrys.theme`, and the only file that writes into the `stylix`
namespace is the adapter, `modules/theme/stylix.nix`. The adapter is exported as
`nixosModules.stylix` and `default` does not import it, so a host without Stylix
imports neither and a host with Stylix imports both. The adapter without the
Stylix module fails at evaluation for the reason above. The Stylix module
without the adapter is not a supported shape either, since the adapter also
declares the Home Manager option that niri-flake's Stylix target reads on a host
where Stylix is imported and off.

The disk layout and the secrets plumbing follow the same rule.
`modules/system/disko.nix` is the only file that writes into the `disko`
namespace and `modules/system/secrets.nix` the only one that writes into `sops`.
Neither is imported by `default` or by `nixosModules.system`, and they are
exported as `nixosModules.disko` and `nixosModules.secrets`. No module in
`default` reads an option of either. Impermanence wipes the device named by its
own option, `othrys.system.impermanence.device`, which the disko export fills
with its LUKS mapping and a host that partitions another way sets itself. Every
module that needs a secret takes a runtime file path and names no provider, so a
host without sops-nix hands those options a path from whatever installs its
secrets.

Impermanence follows it too, although dozens of modules declare a persisted
path. Each of them writes to `othrys.internal.persist`, an option `default`
declares itself, and `modules/system/impermanence.nix` is the only file that
writes into `environment.persistence`. It is exported as
`nixosModules.impermanence` and imported by neither `default` nor
`nixosModules.system`. The `othrys.system.impermanence` options and the root
wipe stay in `default`, in `modules/system/ephemeral-root.nix`, since modules
across the tree read the enable flag and the persist root. A host that turns
impermanence on without the export is rejected by an assertion that names it,
since the root would be wiped and nothing bound back.

Home Manager follows it as well, and nearly every app and desktop module
configures the user. Each of them writes to `othrys.internal.homeConfig`, an
option `default` declares in `modules/system/users.nix` beside
`othrys.system.users.homeManager.enable` and the derived `homeManaged`.
`modules/system/home.nix` is the only file that writes `home-manager.users`,
and it also sets `home-manager.useGlobalPkgs` and `home-manager.useUserPackages`
while `othrys.system.nix` is on. It is exported as `nixosModules.home` and
imported by neither `default` nor `nixosModules.system`. `homeManaged` is true
only on a host that has the account, leaves `homeManager.enable` on and imports
the export, so on a host without it every module behaves as it does for a user
Home Manager does not manage. The registry entries are skipped there and one
warning names them. A host with an account and `homeManager.enable` left on is
rejected without the export by an assertion that names it, since most of those
modules write nothing else and would do nothing at all. A host that wants the
account alone sets `homeManager.enable = false`.

`nixosModules.full` is for the host that wants all five. It imports `default`,
the five exports and the five upstream modules. The upstream modules come from
this flake's own lock, as niri-flake's module does in `default`, and all five
are inputs of this flake already, so no consumer carries an input for them. A
host that uses it imports nothing else and declares no input beside this flake
and nixpkgs. It does not import an upstream module a second time, and it
chooses another revision of one with a `follows` on this flake's input.

**specialArgs stay minimal because they are the one part of the interface the
module system cannot type.** Every additional specialArg is an undeclared
requirement a consumer discovers by hitting an error. The same holds for a name
inside `inputs`, so a module reads a flake from the consumer only when the flake
is the consumer's by nature. That leaves two names. `inputs.nixpkgs` is the
revision the host is built from, which the registry pin has to match, and
`inputs.secrets` is the consumer's own data. Both are read with a fallback, so
a host that passes no specialArgs evaluates.

Every other flake a module builds on comes from this flake's own lock.
`flake/modules.nix` hands ashell, Hyprland, nixvim and nix-index-database to the
modules as the `othrysInputs` argument, and imports niri-flake's module itself,
since a module argument cannot be read in `imports`. A consumer who wants
another build sets the module's `package` option, or makes this flake's input
follow their own. The `eval-inputs` check evaluates a host that is handed no
specialArgs with all four modules on.

## Module Pattern

All modules follow the `othrys.*` namespace convention:

1. Create `modules/{category}/{name}.nix`
1. Define options under `options.othrys.{category}.{name}`
1. Use `lib.mkEnableOption` for the main toggle
1. Guard all config with `config = lib.mkIf cfg.enable { ... };`
1. Write user configuration to `othrys.internal.homeConfig."{category}.{name}"`,
   never to `home-manager.users`
1. Write persistent paths to `othrys.internal.persist."{category}.{name}"`,
   never to `environment.persistence`
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
in {
  options.othrys.{category}.{name} = {
    enable = lib.mkEnableOption "Description";
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

`modules/apps/cli/gh.nix` follows this template, with one persisted directory
and one entry in each registry.

There is no `username` module argument. The primary user comes from
`config.othrys.system.user.name`, and that option has no default, so reading it
on a host that never set it is a hard evaluation error. Any write that touches a
per-user path must therefore sit behind a guard.

Two guards exist, and they are not interchangeable. Account-level writes
(`users.users.<name>`, `/persist` home directories, wipe-script home recreation)
go behind `othrys.system.users.enable`, spelled in the module. Home Manager
writes and persistent paths do not spell a guard at all. A module contributes
to `othrys.internal.homeConfig`, keyed by its own option path, and
`modules/system/home.nix`, exported as `nixosModules.home`, splices the whole
registry into `home-manager.users.<name>` behind
`othrys.system.users.homeManaged`. It
contributes to `othrys.internal.persist` under the same key, and
`modules/system/impermanence.nix` splices that registry into
`environment.persistence`. Nothing else in `modules/` may name
`home-manager.users` or `environment.persistence`, and `contract-guards` in
`flake/checks/` enforces both as prohibitions.

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
- A module does not read evaluated Home Manager output through
  `config.home-manager` either, since that option exists only on a host that
  imports the Home Manager module. A value one Home Manager module needs from
  another is read inside the user's configuration.
  `modules/apps/gui/vscode/default.nix` imports a Home Manager module into its
  registry entry, and that module reads `config.programs.nixvim.build.package`
  there.

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

**Prose that must exist in two places.** Anchor it and add the pair to
`contract-mirror` in `flake/checks/`. The consumer contract is the worked
example. `CONTRIBUTING.md` holds the canonical copy, `docs/src/architecture/`
embeds it through mdbook, and `CLAUDE.md` carries an enforced duplicate because
an agent reads that file automatically and would otherwise have to be told to go
and fetch the contract. Duplication is only dangerous when the copies can
disagree unnoticed, so the hook diffs the two regions and turns the copy into a
mirror. Only one such block exists today, and the hook stays specific to it until
a second one appears.

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

`home.packages` inside the module's `othrys.internal.homeConfig` entry is the
default. User-facing applications and CLI tools live here, which covers
browsers, editors, `yazi` and the language toolchains. They are scoped to the
user and sit beside the program's Home Manager configuration, as in
`modules/apps/gui/discord.nix`.

`environment.systemPackages` is reserved for packages that must exist outside the
user session. That covers system and Nix infrastructure needed in root or sudo
contexts, such as the formatters, linters and rebuild helpers (`alejandra`,
`statix`, `deadnix`, `nvd`, `nix-output-monitor`, `nh`) used by `sudo nixos-rebuild`, `nh os switch` and CI (see `modules/apps/cli/development.nix`).
It also covers packages that must load into a system layer, such as the MangoHud
Vulkan and GL overlay in `modules/apps/gui/gaming/mangohud.nix`, which the
graphics stack injects globally even though its config lives in Home Manager.

When a module needs both a system binary and per-user config, split it. The
package goes in `environment.systemPackages` and the `programs.<name>` settings
go in the module's `othrys.internal.homeConfig` entry, as MangoHud does.

## Impermanence

All persistent state must be declared explicitly. If a module stores state on
disk, declare the persistence in that module rather than in `persistence.nix`.
A module names its paths in `othrys.internal.persist`, under its own option
path, and writes nothing to `environment.persistence`.

```nix
othrys.internal.persist."apps.{app}" = {
  user.directories = [
    ".config/{app}"
    ".local/share/{app}"
  ];
};
```

A system path goes in `directories` or `files`, as in
`modules/services/traefik.nix`.

```nix
othrys.internal.persist."services.{service}" = {
  directories = [
    "/var/lib/{service}"
  ];
};
```

The entries keep the forms the impermanence module accepts, which are a string
or an attribute set with `directory` or `file` and any of `user`, `group` and
`mode`. Paths under `user` are relative to the primary user's home. A module
with a second condition wraps its value in `lib.mkIf`, as
`modules/services/alerting.nix` does, and `lib.mkIf` on one list works as well.

No guard is spelled in the module. `modules/system/impermanence.nix`, exported
as `nixosModules.impermanence`, reads the registry and is the only file that
writes `environment.persistence`. It binds the system paths when
`othrys.system.impermanence.enable` is on and the paths under `user` only when
`othrys.system.users.enable` is on as well, because impermanence dereferences
the account's home directory for every entry under `users`, and a host with
impermanence on and `othrys.system.users.enable` off has no such account.
`contract-guards` rejects any other file that names `environment.persistence`,
and `eval-contract` reads the same rule back from the definitions of two
evaluated hosts. The `eval-persistence` check evaluates the host with no
managed account with every app and desktop module on.

The option `environment.persistence` exists only on a host that imports the
impermanence module, which `nixosModules.default` does not require. A module
that wrote to it directly would fail on every host without that import, with
impermanence on or off.

Three further rules apply to what goes in the list:

- A directory that holds a token, a key or a session gets `mode = "0700"`.
  The home directory is private already, so this is consistency rather than
  containment, and it keeps the mode right when the directory is created by
  the bind mount before the program first runs.
- A directory Home Manager fills with store symlinks and nothing else is not
  persisted. The symlinks are recreated at every activation, so the bind mount
  preserves nothing.
- A file a program saves by writing a temporary and renaming it over the
  original is persisted through its parent directory, never on its own. A
  rename onto a bind-mounted file fails, so a persisted file of that kind
  never takes a save. zsh history is the worked example.

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

Eight hooks run on every commit once the dev shell has installed them, and
`pre-commit-check` runs the same set in `nix flake check`. Both are built from
the two hook sets named in `flake/checks/default.nix`. `comment-hygiene`,
`contract-mirror` and `contract-guards` read this repository's own tree, so
`devShells.consumer`, the shell a consuming flake re-exports, leaves them out.

- **treefmt** formats Nix, shell, TOML, YAML and Markdown (`just fmt`)
- **Statix** lints Nix
- **Deadnix** finds dead code
- **commitizen** checks the commit message against Conventional Commits
- **comment-hygiene** enforces the comment and anchor conventions above
- **contract-mirror** keeps the consumer contract in this file and in
  `CLAUDE.md` identical
- **contract-guards** enforces the consumer contract against `modules/`
- **gitleaks** scans what the commit stages for keys and tokens

## Commit Conventions

- Follow Conventional Commits, `type(scope): subject`, with the module basename
  as the scope. The changelog and the next version number are derived from it
- Use imperative mood, so "add kitty module" rather than "added kitty module"
- Mark a breaking change with `!` and a `BREAKING CHANGE:` footer that says what
  a consumer must do
- Keep the first line under 72 characters

## Signing

Maintainers sign their commits and tags. Release tags are signed annotated tags
cut by `just release`, and `git tag -v <tag>` verifies one. The public keys are
tracked under `keys/`, and the fingerprint is in [SECURITY.md](SECURITY.md).

The `signatures` job of the build workflow verifies every commit of a push to
`main`, and every commit of a pull request opened from a branch of this
repository, against those keys. A commit with no signature, or one signed by
a key that is not in `keys/`, fails the job. A maintainer is added by a
commit that adds their key, signed by a key already listed.

A rebase merge on GitHub rewrites the commits and discards their signatures.
A pull request is therefore opened for review and checks, and once the required
checks pass on its head commit a maintainer fast-forwards `main` to that commit
locally and pushes it. GitHub marks the pull request as merged when its head
reaches `main`.

An outside contribution does not need to be signed by its author, and the job
is skipped for a pull request from a fork. The maintainer who lands it signs
the commits, since a commit on `main` that no listed key signed fails the job.

The weekly input update and Dependabot are treated the same way. Their pull
requests come from the `update_flake_lock_action` and `dependabot/*` branches
of this repository, and their commits carry no signature from a listed key.
The job is skipped for those branches, and the maintainer who lands the bump
signs it.

## Systemd Units

A unit a module defines itself merges `baseline` from `modules/lib/sandbox.nix`
into its `serviceConfig`, then states its exceptions beside it with a comment
saying why each is needed. The user, `RestrictAddressFamilies`, `PrivateUsers`
and `IPAddressDeny` are left to the unit, since no single value suits a unit
that keeps a capability or talks to the network. A unit that cannot take the
baseline says so in a comment.

## Secrets

This repository holds no secrets, and its flake has no `secrets` input. Modules
accept runtime file paths (`passwordFile`, `clientSecretFile` and similar), and
the consuming flake decides what provides them. Never commit a plaintext secret,
and never accept an option design that puts one in the Nix store.

## AI Usage

Contributions made with AI assistance are subject to [AI_POLICY.md](AI_POLICY.md).
