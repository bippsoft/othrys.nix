# modules/hardware/default.nix
# Hardware-specific modules
{
  imports = [
    ./audio.nix
    ./cpu.nix
    ./graphics
    ./laptop
    ./usb.nix
    ./scanner.nix
    ./smart.nix
    ./tablet.nix
    ./ups.nix
    ./webcam.nix
    ./wireless
  ];
}
