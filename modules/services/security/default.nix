# modules/services/security/default.nix
# Security service modules
{
  imports = [
    ./sudo.nix
    ./polkit.nix
    ./yubikey.nixos.nix
    ./fail2ban.nix
    ./crowdsec.nix
  ];
}
