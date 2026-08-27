# modules/system/bootloader.nix
# Bootloader selection (systemd-boot, GRUB, Limine)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.bootloader;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.system.bootloader = {
    enable = lib.mkEnableOption "Bootloader configuration";

    type = lib.mkOption {
      type = lib.types.enum ["limine" "systemd-boot" "grub" "none"];
      default = "limine";
      description = "Bootloader to use.";
    };

    secureBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Secure Boot support.";
    };

    extraEntries = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra boot entries (e.g., Windows dual-boot, for Limine).";
      example = ''
        :Windows 11
            PROTOCOL=chainload_efi
            PATH=boot:///efi/Microsoft/Boot/bootmgfw.efi
      '';
    };
  };

  # ANCHOR: bootloader-config
  config = lib.mkIf cfg.enable {
    boot.loader.efi.canTouchEfiVariables = true;

    boot.loader.limine = lib.mkIf (cfg.type == "limine") {
      enable = true;
      secureBoot.enable = cfg.secureBoot;
      inherit (cfg) extraEntries;
    };

    boot.loader.systemd-boot = lib.mkIf (cfg.type == "systemd-boot") {
      enable = true;
    };

    boot.loader.grub = lib.mkIf (cfg.type == "grub") {
      enable = true;
      efiSupport = true;
      device = "nodev";
    };

    environment.systemPackages = lib.mkIf cfg.secureBoot [
      pkgs.sbctl
    ];

    environment.persistence.${persistRoot} = lib.mkIf (cfg.secureBoot && impermanenceEnabled) {
      directories = [
        {
          directory = "/var/lib/sbctl";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };
  };
  # ANCHOR_END: bootloader-config
}
