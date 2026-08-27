# modules/system/disko.nix
# Declarative disk configuration with LUKS encryption and BTRFS
#
# Layout:
# - EFI boot partition (unencrypted, FAT32)
# - Swap partition (LUKS encrypted)
# - Root partition (LUKS encrypted BTRFS with subvolumes)
#
# BTRFS Subvolumes (Impermanence Layout):
# - root   → /        (ephemeral, wiped on boot)
# - nix    → /nix     (persistent Nix store)
# - persist → /persist (all persistent state)
#
# Usage:
# 1. Configure in host: othrys.system.disko = { enable = true; device = "..."; swapSize = "8G"; };
# 2. Initial install: sudo nix run github:nix-community/disko -- --mode destroy,format,mount --flake .#<host>
# 3. After install, disko config is automatically applied via NixOS
#
# WARNING: Running disko in destroy mode will ERASE ALL DATA on the target disk!
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.disko;
in {
  # ANCHOR: disko-options
  options.othrys.system.disko = {
    enable = lib.mkEnableOption "Disko declarative disk configuration";

    device = lib.mkOption {
      type = lib.types.str;
      description = ''
        Disk device path. Use /dev/disk/by-id/ for reliable identification.
        Find your disk ID with: ls -l /dev/disk/by-id/
      '';
      example = "/dev/disk/by-id/nvme-VENDOR_MODEL_XXXXXXXXXXXXX";
    };

    bootSize = lib.mkOption {
      type = lib.types.str;
      default = "1G";
      description = "EFI boot partition size.";
    };

    swapSize = lib.mkOption {
      type = lib.types.str;
      default = "8G";
      description = ''
        Swap partition size. Recommendations:
        - For hibernation: swap >= RAM size
        - Without hibernation: 4-8GB is usually sufficient
      '';
      example = "16G";
    };

    # Advanced options with sensible defaults
    luks = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "cryptroot";
        description = "Name for the LUKS encrypted root device (appears as /dev/mapper/<name>).";
      };

      swapName = lib.mkOption {
        type = lib.types.str;
        default = "cryptswap";
        description = "Name for the LUKS encrypted swap device (used only when swap.randomEncryption is false).";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a file containing the LUKS passphrase used when disko first
          formats the disk. Leave null (default) to be prompted interactively at
          format time, recommended since at install time sops secrets do not
          yet exist on the target.

          With luks.fido2.enable, this passphrase becomes the break-glass
          recovery keyslot: day-to-day unlock is via YubiKey, and the passphrase
          is only needed if every enrolled key is unavailable. Boot always falls
          back to this passphrase if no token is present.
        '';
        example = lib.literalExpression ''config.sops.secrets."security/boot/password".path'';
      };

      allowDiscards = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TRIM/discard for SSD (recommended for SSDs).";
      };

      bypassWorkqueues = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Bypass dm-crypt workqueues for better SSD performance.";
      };

      fido2.enable = lib.mkEnableOption "FIDO2/YubiKey unlock for the encrypted root (enrolled per-key via `just luks-enroll`; the passphrase stays as break-glass recovery)";
    };

    btrfs = {
      compression = lib.mkOption {
        type = lib.types.str;
        default = "zstd";
        description = "BTRFS compression algorithm for root subvolume.";
      };

      mountOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["noatime" "space_cache=v2"];
        description = "Common BTRFS mount options applied to all subvolumes.";
      };
    };

    swap.randomEncryption = lib.mkOption {
      type = lib.types.bool;
      default = cfg.luks.fido2.enable;
      defaultText = lib.literalExpression "config.othrys.system.disko.luks.fido2.enable";
      description = ''
        Encrypt swap with an ephemeral key generated on each boot instead of a
        persistent LUKS passphrase. Avoids a second unlock prompt at boot
        (recommended with FIDO2) at the cost of hibernation/resume. Defaults to
        luks.fido2.enable.
      '';
    };
  };
  # ANCHOR_END: disko-options

  config = lib.mkIf cfg.enable {
    # FIDO2/YubiKey unlock, which tells the (systemd) initrd to try a FIDO2 token for
    # the root device before prompting for the passphrase. The keyslot itself is
    # added out-of-band via `just luks-enroll` (it lives in the LUKS2 header).
    boot.initrd = lib.mkIf cfg.luks.fido2.enable {
      systemd.enable = true;
      luks.devices.${cfg.luks.name}.crypttabExtraOpts = ["fido2-device=auto"];
    };

    disko.devices = {
      disk = {
        main = {
          inherit (cfg) device;
          type = "disk";

          content = {
            type = "gpt";

            # ANCHOR: disko-partitions
            partitions = {
              # EFI System Partition
              boot = {
                size = cfg.bootSize;
                type = "EF00";
                priority = 1;
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = ["fmask=0077" "dmask=0077" "defaults"];
                };
              };

              # Swap partition (random-key ephemeral, or LUKS with the recovery passphrase)
              swap = {
                size = cfg.swapSize;
                priority = 2;
                content =
                  if cfg.swap.randomEncryption
                  then {
                    # Re-encrypted with a fresh random key each boot, so no second
                    # unlock prompt, but no hibernation/resume.
                    type = "swap";
                    randomEncryption = true;
                  }
                  else {
                    type = "luks";
                    name = cfg.luks.swapName;
                    inherit (cfg.luks) passwordFile;
                    settings = {
                      inherit (cfg.luks) allowDiscards bypassWorkqueues;
                    };
                    content = {
                      type = "swap";
                    };
                  };
              };

              # LUKS Encrypted BTRFS Root
              root = {
                size = "100%";
                priority = 3;
                content = {
                  type = "luks";
                  inherit (cfg.luks) name passwordFile;
                  settings = {
                    inherit (cfg.luks) allowDiscards bypassWorkqueues;
                  };
                  content = {
                    type = "btrfs";
                    extraArgs = ["-f"];

                    # ANCHOR: disko-subvolumes
                    subvolumes = {
                      # Ephemeral root, wiped on every boot
                      "root" = {
                        mountpoint = "/";
                        mountOptions =
                          ["subvol=root" "compress=${cfg.btrfs.compression}"]
                          ++ cfg.btrfs.mountOptions;
                      };

                      # Persistent state, surviving reboots and mounting wherever
                      # the impermanence surface declares its root.
                      "persist" = {
                        mountpoint = config.othrys.system.impermanence.persistRoot;
                        mountOptions = ["subvol=persist"] ++ cfg.btrfs.mountOptions;
                      };

                      # Nix store, persistent
                      "nix" = {
                        mountpoint = "/nix";
                        mountOptions = ["subvol=nix"] ++ cfg.btrfs.mountOptions;
                      };
                    };
                    # ANCHOR_END: disko-subvolumes
                  };
                };
              };
            };
            # ANCHOR_END: disko-partitions
          };
        };
      };
    };
  };
}
