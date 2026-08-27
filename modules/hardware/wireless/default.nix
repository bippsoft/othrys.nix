# modules/hardware/wireless/default.nix
# Wireless hardware modules (Bluetooth, WiFi)
{
  imports = [
    ./bluetooth.nix
    ./wifi.nix
  ];
}
