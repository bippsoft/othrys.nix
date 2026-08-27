# modules/system/impermanence.nix
# Ephemeral root: boot-time BTRFS wipe with an archived snapshot
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.system.impermanence;
  luksName = config.othrys.system.disko.luks.name;
  # Operator tooling for the archive the wipe script maintains, so an admin
  # can browse and copy files out of previous roots. Every mount is
  # READ-ONLY and restore only ever copies out, since archives you cannot
  # inspect are half a safety net.
  oldRoots = pkgs.writeShellApplication {
    name = "old-roots";
    runtimeInputs = [pkgs.util-linux pkgs.coreutils];
    text = ''
      device="/dev/mapper/${luksName}"
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

    fileSystems.${cfg.persistRoot}.neededForBoot = true;
    fileSystems."/nix".neededForBoot = true;

    # The per-user home dir only exists when othrys manages the user account.
    # Headless hosts run impermanence with no primary user.
    systemd.tmpfiles.rules =
      ["d ${cfg.persistRoot}/home 0755 root root -"]
      ++ lib.optionals usersEnabled [
        "d ${cfg.persistRoot}/home/${username} 0700 ${username} users -"
      ];

    # ANCHOR: boot-wipe-script
    boot.initrd.systemd.services.root-wipe = {
      description = "Wipe root BTRFS subvolume for impermanence.";
      wantedBy = ["initrd.target"];
      requires = ["dev-mapper-${luksName}.device"];
      after = ["dev-mapper-${luksName}.device"];
      before = ["sysroot.mount"];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p /btrfs_tmp
        mount /dev/mapper/${luksName} /btrfs_tmp
        if [[ -e /btrfs_tmp/root ]]; then
            mkdir -p /btrfs_tmp/old_roots
            timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%d_%H:%M:%S")
            mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
        fi

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

        # Retention pruning. Data-safety invariants:
        # - `-mindepth 1` so the old_roots directory itself is never a
        #   candidate. Without it, once the directory's own mtime ages past
        #   the window (a host up longer than retentionDays), find returns
        #   old_roots and the ENTIRE archive would be deleted at once.
        # - Only delete entries that are actually btrfs subvolumes, and a stray
        #   file or directory in old_roots is skipped (deleting the unknown is
        #   never the right move in a boot script) and must not fail the boot.
        #
        # Null-delimited so an entry name containing whitespace is one entry.
        # The names are generated timestamps today, and a boot script that
        # deletes subvolumes should not depend on that staying true.
        while IFS= read -r -d ''' i; do
            if btrfs subvolume show "$i" > /dev/null 2>&1; then
                delete_subvolume_recursively "$i"
            else
                echo "impermanence: skipping non-subvolume '$i' in old_roots" >&2
            fi
        done < <(find /btrfs_tmp/old_roots/ -mindepth 1 -maxdepth 1 -mtime +${toString cfg.retentionDays} -print0)

        btrfs subvolume create /btrfs_tmp/root

        ${lib.optionalString usersEnabled "mkdir -p /btrfs_tmp/persist/home/${username}"}

        umount /btrfs_tmp
      '';
    };
    # ANCHOR_END: boot-wipe-script
  };
}
