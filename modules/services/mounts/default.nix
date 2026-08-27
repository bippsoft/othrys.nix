# modules/services/mounts/default.nix
# Non-system filesystem mounts (local disks, CIFS/SMB shares)
{
  imports = [
    ./disks.nix
    ./cifs.nix
  ];
}
