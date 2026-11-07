# modules/system/secrets.nixos.nix
# The NixOS implementation of othrys.system.secrets
#
# Individual secrets are declared in host configs, not here.
#
# Exported as nixosModules.secrets and left out of nixosModules.default, so a
# host imports it together with the sops-nix module or imports neither. It is
# the only file in this tree that writes into the `sops` option namespace.
# Every other module takes a secret as a runtime file path and names no
# provider.
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
      {
        assertion =
          cfg.ageIdentityStubs
          == null
          || !lib.hasInfix "AGE-SECRET-KEY" cfg.ageIdentityStubs;
        message = ''
          othrys.system.secrets.ageIdentityStubs contains an AGE-SECRET-KEY
          identity. That content is written verbatim into a world-readable Nix
          store path, exposing the sops master identity to every user on the
          host and to anything that reads the store. Put the identity behind
          your secrets provider and set ageIdentityFile to its runtime path
          instead.
        '';
      }
      {
        assertion = cfg.ageIdentityStubs == null || cfg.ageIdentityFile == null;
        message = "othrys.system.secrets: set ageIdentityStubs or ageIdentityFile, not both. They both claim SOPS_AGE_KEY_FILE.";
      }
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

    # Tools for secrets management
    environment.systemPackages = with pkgs; [sops age];

    # User config for manual sops editing (YubiKey, etc.). Only when an identity
    # is actually configured, since the homeManaged guard is applied once by
    # nixosModules.home and the condition here is the module's own.
    #
    # The file form points SOPS_AGE_KEY_FILE straight at the provider path, so
    # no identity file is generated and no copy of it exists in the store.
    othrys.internal.homeConfig."system.secrets" = lib.mkIf (cfg.ageIdentityStubs != null || cfg.ageIdentityFile != null) {
      home.file.".config/sops/age/keys.txt" = lib.mkIf (cfg.ageIdentityStubs != null) {
        text = cfg.ageIdentityStubs;
      };
      home.sessionVariables.SOPS_AGE_KEY_FILE =
        if cfg.ageIdentityFile != null
        then cfg.ageIdentityFile
        else "$HOME/.config/sops/age/keys.txt";
    };
  };
}
