# modules/system/secrets.nixos.nix
# The NixOS implementation of othrys.system.secrets
#
# Individual secrets are declared in host configs, not here.
#
# Exported as nixosModules.secrets and left out of nixosModules.default, so a
# host imports it together with the sops-nix module or imports neither. What
# both platforms write is in secrets.nix, and this file points sops-nix at
# the ssh host key and the age key, under the persist root on an
# impermanence host.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.secrets;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  # On impermanence hosts the real key material lives under the persist root
  # (the ephemeral root is wiped every boot). On ordinary hosts it lives in
  # the standard locations. Pointing at the persist root unconditionally
  # would leave non-impermanence hosts with no decryption key at boot.
  persistPrefix = lib.optionalString impermanenceEnabled config.othrys.system.impermanence.persistRoot;
in {
  imports = [./secrets.nix];

  config = lib.mkIf cfg.enable {
    assertions = [
      # The decryption key below is the persisted ssh host key. On an
      # impermanence host that key only exists under the persist root when
      # othrys.system.persistence moves it there, and it only exists at all
      # when sshd generates it. Without either, every secret fails to decrypt
      # at activation with an error about the key rather than about this
      # option, so the pairing is checked here.
      {
        assertion = !impermanenceEnabled || (config.othrys.system.persistence.enable && config.services.openssh.enable);
        message = "othrys.system.secrets: on an impermanence host sops-nix decrypts with the ssh host key under ${config.othrys.system.impermanence.persistRoot}/etc/ssh, which exists only with othrys.system.persistence.enable and services.openssh.enable both on. Enable both, or set sops.age.sshKeyPaths and sops.age.keyFile to a key that is present at activation.";
      }
    ];

    # sops-nix decryption paths, persisted across the root wipe on
    # impermanence hosts and the standard FHS locations otherwise. mkDefault,
    # so a host that keeps its ssh host key elsewhere, or that decrypts with a
    # dedicated age key, points sops-nix at it without mkForce.
    sops.age = {
      sshKeyPaths = lib.mkDefault ["${persistPrefix}/etc/ssh/ssh_host_ed25519_key"];
      keyFile = lib.mkDefault "${persistPrefix}/var/lib/sops-nix/key.txt";
      generateKey = lib.mkDefault true;
    };

    # Tools for secrets management. Each platform file writes the list, so
    # it keeps its place among the NixOS system packages.
    environment.systemPackages = with pkgs; [sops age];
  };
}
