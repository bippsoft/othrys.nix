# modules/services/ssh.nixos.nix
# The NixOS implementation of othrys.services.ssh
#
# ssh.nix writes the known hosts and the user's client configuration,
# which both platforms share, and this file runs the server.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.ssh;
  sshd = import ../lib/sshd.nix {inherit lib;};
in {
  imports = [./ssh.nix];

  config = lib.mkIf cfg.enable {
    services.openssh = lib.mkIf cfg.server.enable {
      enable = true;
      # Both are defaults, so a host that sets the upstream options directly
      # wins. Upstream opens whatever services.openssh.ports ends up holding,
      # which keeps the firewall and the listener on the same list.
      ports = lib.mkDefault cfg.server.ports;
      openFirewall = lib.mkDefault cfg.server.openFirewall;

      # The hardened defaults in ../lib/sshd.nix, each a default so a host
      # can loosen one (e.g. temporary PasswordAuthentication during
      # bootstrap) without lib.mkForce.
      settings = lib.mapAttrs (_: lib.mkDefault) sshd.settings;
    };
  };
}
