# modules/hardware/laptop/powerspec-1710.nix
# PowerSpec 1710 (Clevo PA71HS-G) specific optimizations
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.hardware.laptop.powerspec-1710;
in {
  # nixos-hardware profiles (common-pc-laptop, common-pc-laptop-ssd,
  # common-cpu-intel) are NOT imported here, since imports can't be gated on
  # cfg.enable (they resolve before config), so the host config imports them
  # directly. common-gpu-nvidia stays out entirely, since it causes PRIME assertion
  # failures when loaded unconditionally, and othrys.hardware.nvidia.prime sets
  # proper bus IDs instead.
  options.othrys.hardware.laptop.powerspec-1710 = {
    enable = lib.mkEnableOption "PowerSpec 1710 hardware optimizations";
  };

  config = lib.mkIf cfg.enable {
    # Disable wpa_supplicant (NetworkManager is used instead)
    networking.wireless.enable = lib.mkDefault false;

    # Thermal management (critical for this model)
    services.thermald.enable = lib.mkDefault true;
    boot.kernelModules = ["clevo_wmi"];

    # Thunderbolt 3
    services.hardware.bolt.enable = lib.mkDefault true;

    # Intel microcode
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
