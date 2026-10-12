# Impermanence

The root filesystem is wiped on every boot. Only explicitly declared state persists.

## Importing

The feature has two halves. The `othrys.system.impermanence` options and the
root wipe are part of `nixosModules.default`. The bind mounts that carry state
across the wipe come from the
[impermanence](https://github.com/nix-community/impermanence) module, and
`nixosModules.default` neither imports it nor writes into its options. A host
with a persistent root imports nothing for this page.

A host with an ephemeral root imports the othrys adapter together with the
impermanence module:

```nix
modules = [
  inputs.othrys.nixosModules.default

  inputs.othrys.nixosModules.impermanence
  inputs.impermanence.nixosModules.impermanence
];
```

with `impermanence.follows = "othrys/impermanence";` among the flake inputs.
`nixosModules.full` holds both imports already, so a host built from it adds
neither.

`nixosModules.impermanence` is `modules/system/impermanence.nix`, the only file
in the tree that writes `environment.persistence`. Enabling
`othrys.system.impermanence` without it fails an assertion that names the
export, since the root would be wiped on every boot and nothing bound back. The
adapter without the impermanence module fails at evaluation, because the option
it writes does not exist.

## How It Works

1. BTRFS root subvolume is mounted as `/`
1. On boot, a systemd stage-1 unit moves the old root to `old_roots/` with a timestamp
1. A fresh empty root subvolume is created
1. Old roots older than `retentionDays` are deleted, and a delete that fails is reported and the entry kept

The module turns the systemd initrd on, since the unit exists only there. It
waits for the device named by `othrys.system.impermanence.device` and runs after
a resume from hibernation would have taken over, so a resumed system never meets
a wiped root.

## The device

The wipe needs one fact about the disk, which is the block device holding the
btrfs filesystem with the `root` and `persist` subvolumes. That is
`othrys.system.impermanence.device`, and the module names no partitioning tool.

A host that uses the [disko layout](disko.md) sets nothing. The
`nixosModules.disko` export fills the option with its LUKS mapping,
`/dev/mapper/<luks.name>`, as a default.

A host that partitions another way names the device itself, and needs neither
the disko module nor the export:

```nix
othrys.system.impermanence = {
  enable = true;
  device = "/dev/disk/by-partlabel/root";
};
```

That host also declares the filesystems the layout would have. The `root`
subvolume is mounted at `/`, the `persist` subvolume at
`othrys.system.impermanence.persistRoot`, and `/nix` on a volume the wipe does
not touch. The module marks the last two as needed for boot. For an encrypted
root the device is the opened mapping, such as `/dev/mapper/cryptroot`, and not
the partition under it.

Enabling impermanence with no device and no layout fails an assertion that names
the option.

## Options

```nix
{{#include ../../../modules/system/ephemeral-root.nix:impermanence-options}}
```

## Boot Wipe Script

Runs during early boot (initrd), after resume from hibernation but before root is mounted:

```bash
{{#include ../../../modules/system/ephemeral-root.nix:boot-wipe-script}}
```

## The Persistence Registry

A module declares what it keeps across the wipe in `othrys.internal.persist`,
under a key that is its own option path. It does not write
`environment.persistence`.

```nix
{{#include ../../../modules/system/persistence.nix:persist-registry}}
```

Each value holds `directories` and `files` for system paths, and
`user.directories` and `user.files` for paths in the primary user's home. An
entry is a string, or an attribute set with `directory` or `file` and any of
`user`, `group` and `mode`, which are the forms the impermanence module accepts.

The adapter reads the whole registry and writes it under
`othrys.system.impermanence.persistRoot`:

```nix
{{#include ../../../modules/system/impermanence.nix:persist-splice}}
```

Both guards live there. With impermanence off nothing is declared. With no
managed account the paths under `user` are left out, since the impermanence
module reads `users.users.<name>.home` to place each bind mount and that
account does not exist. A host of that shape, with every app and desktop module
on, is what the `eval-persistence` check evaluates. `contract-guards` rejects
any other file that names `environment.persistence`, and `eval-contract` reads
the writers back from two evaluated hosts.

A host adds paths of its own either way. It writes a key of its own in
`othrys.internal.persist`, or it writes `environment.persistence` directly,
which merges with what the adapter declares.

## System Persistence

System-critical directories persisted in `persistence.nix`:

```nix
{{#include ../../../modules/system/persistence.nix:system-persistence}}
```

`/etc/machine-id` is in the set because the journal directory and the
systemd-networkd DHCP identity are both derived from it. Without it every boot
produces a new id.

A host that was already running when it first switches onto this gets its
current id kept. impermanence refuses to mount over a machine-id file that
already holds an id, so an activation step in the adapter copies the running id
into the persist root and bind-mounts it before impermanence looks. A persisted file that
is missing, empty or a leftover symlink is replaced, and one holding a different
id is kept beside it as `machine-id.replaced`. At boot the step does nothing.

`/nix/var` is not in the set. The `nix` subvolume survives the wipe on its own,
so the database, the profiles and the GC roots stay where the installer put
them. Releases before v0.9.0 persisted it, and v0.9.0 to v0.16.0 carried an
activation step that moved such a host onto the subvolume at its first switch.
The step is gone, so a host that still bind-mounts `<persistRoot>/nix/var`
switches to one of those releases first.

The SSH host keys are not bind-mounted. `services.openssh.hostKeys` points at
`<persistRoot>/etc/ssh/` directly, which is also where sops-nix reads the
ed25519 key. A bind mount over `/etc/ssh` would cover the `sshd_config` that
activation writes, and `sshd` on a freshly installed host would not start until
the first switch.

## User Persistence

Cross-cutting user directories (XDG, SSH, Projects):

```nix
{{#include ../../../modules/system/persistence.nix:user-persistence}}
```

Every entry under `user` is bound only when `othrys.system.users.enable` is on
as well as impermanence, here and for each app module. The adapter applies
that guard, as described above, and no module spells it.

Directories that hold a token, a key or a session are persisted at mode
`0700`. A file a program saves by renaming a temporary over it, such as zsh
history, is persisted through its directory, since a rename onto a
bind-mounted file fails.

## App-Specific Persistence

Each module declares its own persistence:

```nix
{{#include ../../../modules/system/persistence.nix:app-persistence-index}}
```

## Recovering files from a previous boot

The wipe archives each replaced root under `old_roots` for
`retentionDays`. The `old-roots` tool (installed with this module) browses
that archive, since every mount is read-only and `restore` only copies out:

```bash
old-roots list                          # archived snapshots (timestamps)
old-roots restore <snapshot> home/alice/notes.txt ./notes.txt
old-roots mount                         # browse under /run/old-roots/old_roots
old-roots umount
```

The recovery path is exercised by the impermanence VM test alongside the
wipe behavior itself. A second VM test boots the unit itself from a btrfs root
across three boots, so the initrd rendering, the device dependency and the
stage-1 PATH are covered as well as the script.
