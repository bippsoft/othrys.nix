# Impermanence

The root filesystem is wiped on every boot. Only explicitly declared state persists.

## How It Works

1. BTRFS root subvolume is mounted as `/`
1. On boot, the initrd script moves the old root to `old_roots/` with a timestamp
1. Old roots older than 30 days are deleted
1. A fresh empty root subvolume is created

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
wipe behavior itself.
