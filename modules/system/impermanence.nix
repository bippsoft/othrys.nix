# modules/system/impermanence.nix
# Ephemeral root: boot-time BTRFS wipe with an archived snapshot
{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.system.impermanence;
  luksName = config.othrys.system.disko.luks.name;
  # systemd names a device unit after the escaped path, so a LUKS name with a
  # hyphen is `dev-mapper-crypt\x2droot.device`, not `dev-mapper-crypt-root`.
  deviceUnit = "${utils.escapeSystemdPath cfg.device}.device";
  # Operator tooling for the archive the wipe script maintains, so an admin
  # can browse and copy files out of previous roots. Every mount is
  # READ-ONLY and restore only ever copies out, since archives you cannot
  # inspect are half a safety net.
  oldRoots = pkgs.writeShellApplication {
    name = "old-roots";
    runtimeInputs = [pkgs.util-linux pkgs.coreutils];
    text = ''
      device=${lib.escapeShellArg cfg.device}
      mnt="/run/old-roots"

      ensure_mounted() {
        mkdir -p "$mnt"
        mountpoint -q "$mnt" || mount -o ro "$device" "$mnt"
      }

      case "''${1:-}" in
        list)
          ensure_mounted
          if [ -d "$mnt/old_roots" ]; then
            ls -1 "$mnt/old_roots"
          else
            echo "no archived roots"
          fi
          umount "$mnt"
          ;;
        mount)
          ensure_mounted
          echo "archive mounted read-only; snapshots under $mnt/old_roots"
          echo "run 'old-roots umount' when done"
          ;;
        umount)
          umount "$mnt"
          ;;
        restore)
          snapshot="''${2:?usage: old-roots restore <snapshot> <path> [dest]}"
          path="''${3:?usage: old-roots restore <snapshot> <path> [dest]}"
          dest="''${4:-./$(basename "$path").restored}"
          ensure_mounted
          src="$mnt/old_roots/$snapshot/$path"
          if [ ! -e "$src" ]; then
            echo "error: $src does not exist" >&2
            umount "$mnt"
            exit 1
          fi
          cp -a "$src" "$dest"
          umount "$mnt"
          echo "restored to $dest"
          ;;
        *)
          echo "usage: old-roots <list|mount|umount|restore <snapshot> <path> [dest]>"
          exit 1
          ;;
      esac
    '';
  };
in {
  # ANCHOR: impermanence-options
  options.othrys.system.impermanence = {
    enable = lib.mkEnableOption "Impermanence (ephemeral root with opt-in persistence)";

    persistRoot = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = ''
        Mountpoint of the persistent volume. Every othrys module keys its
        `environment.persistence` declarations on this path, and the disko
        layout mounts the persist subvolume here, so one option moves the whole
        persistence surface. The btrfs subvolume itself is still named
        `persist` (the boot-wipe script addresses subvolumes, not mounts).
      '';
    };

    retentionDays = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 30;
      description = "Days to keep old root snapshots in /btrfs_tmp/old_roots before deletion.";
    };

    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/mapper/${luksName}";
      defaultText = lib.literalExpression ''"/dev/mapper/''${config.othrys.system.disko.luks.name}"'';
      description = ''
        Block device holding the btrfs filesystem with the `root` and
        `persist` subvolumes. The wipe unit waits for this device in the initrd
        and mounts its top-level subvolume. The default is the disko LUKS
        mapping; a host whose btrfs sits on a plain partition names that
        partition here.
      '';
      example = "/dev/disk/by-partlabel/root";
    };
  };
  # ANCHOR_END: impermanence-options

  config = lib.mkIf cfg.enable {
    # The boot-wipe service targets the disko LUKS/btrfs layout (luksName +
    # the root/persist/nix subvolumes). othrys.system.disko produces exactly
    # that layout by construction, so disko.enable is the invariant. If disko
    # ever grows alternative layouts (ext4/ZFS/no-LUKS), this assertion must
    # be strengthened to check the actual btrfs+LUKS shape the script mounts.
    assertions = [
      {
        assertion = config.othrys.system.disko.enable;
        message = "othrys.system.impermanence requires othrys.system.disko.enable (the boot-wipe service targets the disko LUKS/btrfs layout).";
      }
    ];

    environment.systemPackages = [oldRoots];

    # The wipe is a systemd stage-1 unit. The scripted initrd ignores
    # boot.initrd.systemd.services without an error, so a host that did not
    # turn the systemd initrd on for another reason kept its root forever.
    boot.initrd.systemd.enable = true;
    # The stage-1 PATH is coreutils, util-linux and btrfs-progs. The prune
    # loop below needs nothing else, and findutils is here so a later edit
    # that reaches for `find` keeps working in stage 1 too.
    boot.initrd.systemd.initrdBin = [pkgs.findutils];

    fileSystems.${cfg.persistRoot}.neededForBoot = true;
    fileSystems."/nix".neededForBoot = true;

    # The per-user home dir only exists when othrys manages the user account.
    # Headless hosts run impermanence with no primary user.
    systemd.tmpfiles.rules =
      ["d ${cfg.persistRoot}/home 0755 root root -"]
      ++ lib.optionals usersEnabled [
        # The group comes from the account rather than a literal "users", since
        # a host is free to give its primary user a different primary group.
        "d ${cfg.persistRoot}/home/${username} 0700 ${username} ${config.users.users.${username}.group} -"
      ];

    # ANCHOR: boot-wipe-script
    boot.initrd.systemd.services.root-wipe = {
      description = "Wipe root BTRFS subvolume for impermanence.";
      wantedBy = ["initrd.target"];
      requires = [deviceUnit];
      # A resume from hibernation never returns from the resume unit, so this
      # only runs on a boot that is not a resume. Without the ordering the
      # wipe could run first and the resumed image would see a root that is no
      # longer the one it had mounted.
      after = [deviceUnit "systemd-hibernate-resume.service"];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /btrfs_tmp
        # subvolid=5 names the top-level subvolume. A host whose default
        # subvolume was changed with `btrfs subvolume set-default` would
        # otherwise mount that one and find no `root` to move.
        mount -o subvolid=5 ${lib.escapeShellArg cfg.device} /btrfs_tmp
        if [[ -e /btrfs_tmp/root ]]; then
            mkdir -p /btrfs_tmp/old_roots
            timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%d_%H:%M:%S")
            mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
        fi

        # The new root exists before anything that can fail below runs. A
        # prune that aborted between the move and this line left the host
        # with no root subvolume, and sysroot.mount dropped it into the
        # emergency shell.
        btrfs subvolume create /btrfs_tmp/root

        ${lib.optionalString usersEnabled "mkdir -p /btrfs_tmp/persist/home/${username}"}

        # `local IFS` keeps the split scoped to this function. Assigned
        # globally it survived the first call and silently changed how every
        # later word split behaved, including the retention loop below.
        delete_subvolume_recursively() {
            local IFS=$'\n'
            for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                delete_subvolume_recursively "/btrfs_tmp/$i"
            done
            btrfs subvolume delete "$1"
        }

        # Retention pruning, best-effort. Data-safety invariants:
        # - The glob lists the entries of old_roots and never old_roots
        #   itself, so an archive directory whose own mtime has aged past the
        #   window (a host up longer than retentionDays) is not a candidate.
        #   With `find` and no `-mindepth 1` it was, and the ENTIRE archive
        #   would be deleted at once.
        # - Only delete entries that are actually btrfs subvolumes, and a stray
        #   file or directory in old_roots is skipped (deleting the unknown is
        #   never the right move in a boot script) and must not fail the boot.
        # - A delete that fails is reported and the entry kept. The root above
        #   already exists, so nothing here can keep the host from booting.
        #
        # A glob with nullglob handles an empty archive and an entry name with
        # whitespace. The names are generated timestamps today, and a boot
        # script that deletes subvolumes should not depend on that staying
        # true. `find` is not on the stage-1 PATH, which is why the loop uses
        # `stat` instead; see initrdBin above.
        shopt -s nullglob
        cutoff=$(( $(date +%s) - ${toString cfg.retentionDays} * 86400 ))
        for i in /btrfs_tmp/old_roots/*; do
            if [ "$(stat -c %Y "$i")" -ge "$cutoff" ]; then
                continue
            fi
            if btrfs subvolume show "$i" > /dev/null 2>&1; then
                delete_subvolume_recursively "$i" \
                    || echo "impermanence: could not delete '$i', keeping it" >&2
            else
                echo "impermanence: skipping non-subvolume '$i' in old_roots" >&2
            fi
        done
        shopt -u nullglob

        umount /btrfs_tmp
      '';
    };
    # ANCHOR_END: boot-wipe-script
  };
}
