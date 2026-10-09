# Impermanence

The root filesystem is wiped on every boot. Only explicitly declared state persists.

## How It Works

1. BTRFS root subvolume is mounted as `/`
1. On boot, a systemd stage-1 unit moves the old root to `old_roots/` with a timestamp
1. A fresh empty root subvolume is created
1. Old roots older than `retentionDays` are deleted, and a delete that fails is reported and the entry kept

The module turns the systemd initrd on, since the unit exists only there. It
waits for the device named by `othrys.system.impermanence.device`, which is the
disko LUKS mapping by default, and runs after a resume from hibernation would
have taken over, so a resumed system never meets a wiped root.

## Options

```nix
{{#include ../../../modules/system/impermanence.nix:impermanence-options}}
```

## Boot Wipe Script

Runs during early boot (initrd), after resume from hibernation but before root is mounted:

```bash
{{#include ../../../modules/system/impermanence.nix:boot-wipe-script}}
```

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
already holds an id, so an activation step copies the running id into the
persist root and bind-mounts it before impermanence looks. A persisted file that
is missing, empty or a leftover symlink is replaced, and one holding a different
id is kept beside it as `machine-id.replaced`. At boot the step does nothing.

`/nix/var` is not in the set. The `nix` subvolume survives the wipe on its own,
so the database, the profiles and the GC roots stay where the installer put
them. Earlier releases persisted it, which hid the install-time database on a
fresh host's first boot. A host that ran under that configuration is moved
onto the subvolume by an activation step at its first switch: the live copy is
reflinked onto the subvolume under Nix's own lock, the bind mount is dropped,
and the two copies that existed before are kept as `/nix/var.install` and
`<persistRoot>/nix/var.migrated` for the operator to remove. If the unmount is
refused because something holds a file under `/nix/var`, the mount stays and
the move finishes at the next boot. A host that was installed under the old
configuration and rebooted but never switched holds its install-time database
in `var.install` and a near-empty one under the persist root; compare the two
before removing either. The step is transitional and is removed in a release
before v1.0.0.

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
