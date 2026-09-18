# modules/system/bootloader.nix
# Bootloader selection (systemd-boot, GRUB, Limine)
{
  config,
  lib,
  options,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.bootloader;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # Lanzaboote is an optional import. nixosModules.default does not pull it in,
  # so its option namespace exists only when the consuming flake imports
  # lanzaboote.nixosModules.lanzaboote itself.
  hasLanzaboote = options.boot ? lanzaboote;
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
      description = ''
        Sign the boot chain with the sbctl keys in `/var/lib/sbctl`. Limine
        signs natively. systemd-boot is signed through lanzaboote, which the
        consuming flake must import as `lanzaboote.nixosModules.lanzaboote`.
        GRUB and `"none"` are rejected. The keys must exist before the first
        rebuild, and the firmware enforces nothing until they are enrolled.
      '';
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
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !(cfg.secureBoot && cfg.type == "systemd-boot") || hasLanzaboote;
          message = "othrys.system.bootloader: secureBoot with type = \"systemd-boot\" requires lanzaboote. Add lanzaboote as a flake input and import lanzaboote.nixosModules.lanzaboote in the host's modules.";
        }
        {
          assertion = !(cfg.secureBoot && cfg.type == "grub");
          message = "othrys.system.bootloader: GRUB has no Secure Boot support in NixOS. Set type to \"limine\" or \"systemd-boot\", or set secureBoot = false.";
        }
        {
          assertion = !(cfg.secureBoot && cfg.type == "none");
          message = "othrys.system.bootloader: secureBoot does nothing with type = \"none\", since this module manages no bootloader there. Set type to \"limine\" or \"systemd-boot\", or set secureBoot = false.";
        }
      ];

      boot.loader.efi.canTouchEfiVariables = true;

      boot.loader.limine = lib.mkIf (cfg.type == "limine") {
        enable = true;
        secureBoot.enable = cfg.secureBoot;
        inherit (cfg) extraEntries;
      };

      # Lanzaboote installs and signs systemd-boot itself, so the stock module
      # goes off whenever lanzaboote takes over. Without the lanzaboote import
      # it stays on. Turning it off there leaves NixOS on its default GRUB,
      # whose own assertion then fails beside the one above.
      boot.loader.systemd-boot = lib.mkIf (cfg.type == "systemd-boot") {
        enable = !(cfg.secureBoot && hasLanzaboote);
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
    }

    # The guard sits on the attrset because mkIf does not defer option
    # existence. A conditional write into boot.lanzaboote still fails on a
    # host that never imported the module.
    (lib.optionalAttrs hasLanzaboote {
      boot.lanzaboote = lib.mkIf (cfg.type == "systemd-boot" && cfg.secureBoot) {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
      };
    })
  ]);
  # ANCHOR_END: bootloader-config
}
