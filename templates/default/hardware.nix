# Placeholder so the template evaluates. Replace it with the output of
# `nixos-generate-config --show-hardware-config`, or remove the root filesystem
# here and describe the disk with othrys.system.disko instead.
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };
}
