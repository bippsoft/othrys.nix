# modules/services/mounts/disks.nix
# Additional disk mounting configuration
# Supports multiple disks with different filesystems (NTFS, ext4, btrfs, etc.)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.services.mounts.disks;

  # Generate mount options based on filesystem type
  mkMountOptions = disk: let
    automountOpts = lib.optionals disk.automount [
      "nofail"
      "x-systemd.automount"
      "x-systemd.device-timeout=${toString disk.deviceTimeout}"
    ];
  in
    if disk.fsType == "ntfs-3g"
    then
      [
        "rw"
        "uid=${toString disk.uid}"
        "gid=${toString disk.gid}"
        "dmask=${disk.dmask}"
        "fmask=${disk.fmask}"
        "big_writes"
        "windows_names"
      ]
      ++ disk.extraOptions
      ++ automountOpts
    else if disk.fsType == "ntfs3"
    then
      # In-kernel NTFS driver (no big_writes, which is FUSE-only)
      [
        "uid=${toString disk.uid}"
        "gid=${toString disk.gid}"
        "dmask=${disk.dmask}"
        "fmask=${disk.fmask}"
        "windows_names"
      ]
      ++ disk.extraOptions
      ++ automountOpts
    else if disk.fsType == "vfat"
    then
      # FAT stores no owner and no mode, so without these every file belongs
      # to root. It cannot hold a real setuid binary or device node either,
      # and nosuid and nodev keep the kernel from honouring anything a
      # crafted image presents as one.
      [
        "uid=${toString disk.uid}"
        "gid=${toString disk.gid}"
        "dmask=${disk.dmask}"
        "fmask=${disk.fmask}"
        "nosuid"
        "nodev"
      ]
      ++ disk.extraOptions
      ++ automountOpts
    else
      # ext4, btrfs, xfs, etc.
      disk.extraOptions ++ automountOpts;

  # Disk submodule type
  diskType = lib.types.submodule {
    options = {
      device = lib.mkOption {
        type = lib.types.str;
        description = "Device path (use /dev/disk/by-uuid/ or /dev/disk/by-partuuid/).";
        example = "/dev/disk/by-uuid/0123456789ABCDEF";
      };

      mountPoint = lib.mkOption {
        type = lib.types.str;
        description = "Mount point path.";
        example = "/mnt/data";
      };

      fsType = lib.mkOption {
        type = lib.types.enum ["ntfs-3g" "ntfs3" "ext4" "btrfs" "xfs" "vfat"];
        default = "ext4";
        description = "Filesystem type (ntfs-3g = FUSE driver, ntfs3 = in-kernel driver).";
      };

      uid = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 1000;
        description = "User ID that owns the files (NTFS and vfat, which store no owner).";
      };

      gid = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 100;
        description = "Group ID that owns the files (NTFS and vfat).";
      };

      dmask = lib.mkOption {
        type = lib.types.str;
        default = "022";
        description = "Directory permission mask (NTFS and vfat).";
      };

      fmask = lib.mkOption {
        type = lib.types.str;
        default = "133";
        description = "File permission mask (NTFS and vfat).";
      };

      automount = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Auto-mount on access with nofail.";
      };

      deviceTimeout = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Timeout in seconds if device not found.";
      };

      extraOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra mount options.";
      };
    };
  };

  # Collect required filesystem types
  requiredFilesystems = lib.unique (
    lib.mapAttrsToList (_: disk:
      if disk.fsType == "ntfs-3g"
      then "ntfs"
      else if disk.fsType == "ntfs3"
      then "ntfs3"
      else disk.fsType)
    cfg.devices
  );

  # Check if NTFS is needed
  needsNtfs = lib.any (disk: disk.fsType == "ntfs-3g") (lib.attrValues cfg.devices);
in {
  # ANCHOR: disks-options
  options.othrys.services.mounts.disks = {
    enable = lib.mkEnableOption "additional disk mounts";

    devices = lib.mkOption {
      type = lib.types.attrsOf diskType;
      default = {};
      description = "Disk mount configurations.";
      example = lib.literalExpression ''
        {
          data = {
            device = "/dev/disk/by-uuid/0123456789ABCDEF";
            mountPoint = "/mnt/data";
            fsType = "ntfs-3g";
          };
          backup = {
            device = "/dev/disk/by-uuid/abcd1234-5678-90ab-cdef";
            mountPoint = "/mnt/backup";
            fsType = "ext4";
          };
        }
      '';
    };
  };
  # ANCHOR_END: disks-options

  config = lib.mkIf (cfg.enable && cfg.devices != {}) {
    # Generate fileSystems entries for each disk
    fileSystems = lib.mapAttrs' (_: disk:
      lib.nameValuePair disk.mountPoint {
        inherit (disk) device fsType;
        options = mkMountOptions disk;
        neededForBoot = false;
      })
    cfg.devices;

    # Enable required filesystem support
    boot.supportedFilesystems = requiredFilesystems;

    # Install required filesystem tools
    environment.systemPackages = lib.optionals needsNtfs [pkgs.ntfs3g];
  };
}
