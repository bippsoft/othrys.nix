# modules/hardware/cpu.nix
# CPU microcode, firmware and KVM support for a host that runs on its own processor
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.hardware.cpu;
in {
  # ANCHOR: cpu-options
  options.othrys.hardware.cpu = {
    vendor = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["intel" "amd"]);
      default = null;
      example = "intel";
      description = ''
        The processor's vendor, on a host that runs on its own hardware. It
        turns on microcode updates for that vendor, the redistributable
        firmware the microcode and most devices load, and the vendor's KVM
        module. `null` writes nothing, which suits a virtual machine, where
        the hypervisor owns the microcode.
      '';
    };
  };
  # ANCHOR_END: cpu-options

  config = lib.mkIf (cfg.vendor != null) {
    # nixos-generate-config writes these three into hardware.nix, and a host
    # installed another way, as with disko, has none of them. NixOS defaults
    # every one to off, so such a host runs the microcode its board shipped.
    hardware.cpu.${cfg.vendor}.updateMicrocode = true;
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    boot.kernelModules = ["kvm-${cfg.vendor}"];
  };
}
