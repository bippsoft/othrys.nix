# modules/system/disko.nix
# Declarative disk layout with LUKS encryption and BTRFS subvolumes
#
# The disk carries an unencrypted FAT32 EFI partition, an encrypted swap
# partition and an encrypted BTRFS root. The root holds three subvolumes.
# `root` is mounted at / and is the one othrys.system.impermanence wipes on
# boot, `nix` holds the Nix store, and `persist` holds all persistent state.
#
# disko formats the disk once, at install, in a mode that erases the target
# disk. After that the same declaration supplies the host's filesystems.
{
  config,
  lib,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.system.disko;

  # cryptsetup falls back to defaults compiled into its build for whatever
  # luksFormat is not told, and those have changed between releases. Stating
  # them makes two installs from one revision produce the same header. The
  # values are the current upstream defaults for LUKS2, which is AES-XTS with
  # a 512-bit key (two 256-bit halves), SHA-256 for the header digest and
  # Argon2id for the passphrase. They apply when disko formats the disk and
  # never touch an existing volume.
  luksFormatArgs = [
    "--type luks2"
    "--cipher aes-xts-plain64"
    "--key-size 512"
    "--hash sha256"
    "--pbkdf argon2id"
  ];
in {
  # ANCHOR: disko-options
  options.othrys.system.disko = {
    enable = lib.mkEnableOption "Disko declarative disk configuration";

    device = lib.mkOption {
      type = lib.types.str;
      description = ''
        Disk device path. Use /dev/disk/by-id/ for reliable identification.
        Find your disk ID with: ls -l /dev/disk/by-id/

        A path outside /dev/disk/, such as /dev/sda, evaluates with a
        warning. The kernel hands those names out in probe order, so the same
        name can be another disk on the next boot.
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
        type = lib.types.nullOr othrysTypes.secretPath;
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
        description = ''
          Pass TRIM requests through dm-crypt to the SSD. The requests show an
          observer of the raw disk which blocks are free, which is the price
          of keeping the drive's performance. `services.fstrim.enable`
          follows this option, since the passthrough alone discards nothing.
        '';
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
    warnings = lib.optional (!lib.hasPrefix "/dev/disk/" cfg.device) "othrys.system.disko.device is ${cfg.device}, a name the kernel assigns in probe order. disko formats whatever disk carries that name at install time, and the host waits in the initrd if it moves afterwards. Use a path under /dev/disk/by-id/.";

    # allowDiscards only lets a discard through the encryption layer, and no
    # subvolume is mounted with one, so something has to issue it. The weekly
    # fstrim timer is that. mkDefault leaves a host free to mount with
    # discard=async instead.
    services.fstrim.enable = lib.mkDefault cfg.luks.allowDiscards;

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
                    extraFormatArgs = luksFormatArgs;
                    settings = {
                      inherit (cfg.luks) allowDiscards bypassWorkqueues;
                    };
                    content = {
                      type = "swap";
                      # Without a discard policy swap never trims, whatever
                      # the LUKS layer allows, so it follows allowDiscards.
                      discardPolicy = lib.mkIf cfg.luks.allowDiscards "both";
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
                  extraFormatArgs = luksFormatArgs;
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
