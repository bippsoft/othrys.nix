# modules/services/default.nix
# Service modules
{
  imports = [
    ./docs.nix
    ./ssh.nix
    ./tailscale.nix
    ./headscale.nix
    ./monitoring.nix
    ./victoriametrics.nix
    ./victorialogs.nix
    ./grafana.nix
    ./alerting.nix
    ./scrutiny.nix
    ./ntfy.nix
    ./notify.nix
    ./wireguard.nix
    ./ddns.nix
    ./automount.nix
    ./virtualcamera.nix
    ./firewall.nix
    ./kea.nix
    ./printing.nix
    ./router.nix
    ./suricata.nix
    ./unbound.nix
    ./restic.nix
    ./traefik.nix
    ./security
    ./containerization
    ./mounts
  ];
}
