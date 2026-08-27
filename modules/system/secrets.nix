# modules/system/secrets.nix
# sops-nix infrastructure, providing age decryption capability
# Individual secrets are declared in host configs, not here
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.system.secrets;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  # On impermanence hosts the real key material lives under the persist root
  # (the ephemeral root is wiped every boot). On ordinary hosts it lives in
  # the standard locations. Pointing at the persist root unconditionally
  # would leave non-impermanence hosts with no decryption key at boot.
  persistPrefix = lib.optionalString impermanenceEnabled config.othrys.system.impermanence.persistRoot;
in {
  # ANCHOR: secrets-options
  options.othrys.system.secrets = {
    enable = lib.mkEnableOption "sops-nix secrets infrastructure";

    # Expose secrets repo paths for host configs to reference
    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = inputs.secrets.secretFiles or {};
      readOnly = true;
      description = "Available secret files from the secrets repository.";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = "Age identity for manual sops editing (e.g., YubiKey plugin line).";
    };
  };
  # ANCHOR_END: secrets-options

  config = lib.mkIf cfg.enable {
    # Configure sops-nix decryption paths (persisted across the root wipe on
    # impermanence hosts, standard FHS locations otherwise)
    sops.age = {
      sshKeyPaths = ["${persistPrefix}/etc/ssh/ssh_host_ed25519_key"];
      keyFile = "${persistPrefix}/var/lib/sops-nix/key.txt";
      generateKey = true;
    };

    # Tools for secrets management
    environment.systemPackages = with pkgs; [sops age];

    # User config for manual sops editing (YubiKey, etc.). Guarded at the
    # attrset level, since a leaf-level mkIf would still materialize the HM user on
    # headless hosts (see modules/system/nix.nix).
    home-manager.users = lib.mkIf (hmEnabled && cfg.ageKeyFile != null) {
      ${username} = {
        home.file.".config/sops/age/keys.txt".text = cfg.ageKeyFile;
        home.sessionVariables.SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
      };
    };
  };
}
