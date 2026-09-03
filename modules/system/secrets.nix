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
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.system.secrets;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  # On impermanence hosts the real key material lives under the persist root
  # (the ephemeral root is wiped every boot). On ordinary hosts it lives in
  # the standard locations. Pointing at the persist root unconditionally
  # would leave non-impermanence hosts with no decryption key at boot.
  persistPrefix = lib.optionalString impermanenceEnabled config.othrys.system.impermanence.persistRoot;

  # othrys declares no `secrets` input of its own. A consuming flake may add
  # one, and when it does this module reads `secretFiles` from it. The contract
  # is documented on the option below and in the README.
  #
  # The read used to be `inputs.secrets.secretFiles or {}`, which swallowed a
  # typo'd input name and a malformed attribute alike, leaving hosts to fail
  # much later with a missing sops file. Absent stays an empty default, while
  # present-but-wrong fails here and says what is wrong.
  secretsInput =
    if !(inputs ? secrets)
    then {}
    else if !(inputs.secrets ? secretFiles)
    then
      throw ''
        othrys.system.secrets: the `secrets` flake input exists but exposes no
        `secretFiles` output. othrys expects an attrset of names to encrypted
        sops files, for example { common = ./common.yaml; }. Add the output, or
        remove the input and set othrys.system.secrets.secretFiles consumers
        need by hand.
      ''
    else if !(builtins.isAttrs inputs.secrets.secretFiles)
    then
      throw ''
        othrys.system.secrets: the `secrets` flake input exposes `secretFiles`
        but it is a ${builtins.typeOf inputs.secrets.secretFiles} rather than an
        attrset. othrys expects an attrset of names to encrypted sops files, for
        example { common = ./common.yaml; }.
      ''
    else inputs.secrets.secretFiles;
in {
  # ANCHOR: secrets-options
  options.othrys.system.secrets = {
    enable = lib.mkEnableOption "sops-nix secrets infrastructure";

    # Expose secrets repo paths for host configs to reference
    secretFiles = lib.mkOption {
      # Deliberately lib.types.path. These are ENCRYPTED sops files from the
      # secrets input, read at evaluation, so the store is where they belong.
      type = lib.types.attrsOf lib.types.path;
      default = secretsInput;
      defaultText = lib.literalExpression "inputs.secrets.secretFiles, or {} when no secrets input is declared";
      readOnly = true;
      description = ''
        Encrypted sops files, read from an optional `secrets` flake input in
        the consuming flake. othrys declares no such input itself.

        The contract is that when a consumer declares an input named `secrets`,
        it exposes `secretFiles` as an attrset of names to encrypted files, for
        example `{ common = ./common.yaml; host-atlas = ./atlas.yaml; }`.
        Declaring no `secrets` input is fine and leaves this empty. Declaring
        one that does not match the shape is an evaluation error rather than a
        silently empty attrset.
      '';
    };

    ageIdentityStubs = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      example = ''
        #recipient: age1yubikey1qw3na0f9example...
        AGE-PLUGIN-YUBIKEY-1EXAMPLE...
      '';
      description = ''
        Age identity lines for manual sops editing, written to
        `~/.config/sops/age/keys.txt`.

        The content becomes a world-readable Nix store path, so this option is
        safe only for identities that hold no key material on their own. An
        age-plugin-yubikey stub qualifies, since the private key never leaves
        the token and the stub is only a pointer to it. A raw
        `AGE-SECRET-KEY-1...` does not, and an assertion rejects one. Use
        ageIdentityFile for anything secret.
      '';
    };

    ageIdentityFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = "/run/secrets/sops/age-identity";
      description = ''
        Runtime path to an age identity file, pointed at by SOPS_AGE_KEY_FILE
        for manual sops editing. The required form for an identity that
        contains key material, since the file is read from the secrets provider
        at use time and nothing is copied into the store.
      '';
    };
  };
  # ANCHOR_END: secrets-options

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
    ];

    # Configure sops-nix decryption paths (persisted across the root wipe on
    # impermanence hosts, standard FHS locations otherwise)
    sops.age = {
      sshKeyPaths = ["${persistPrefix}/etc/ssh/ssh_host_ed25519_key"];
      keyFile = "${persistPrefix}/var/lib/sops-nix/key.txt";
      generateKey = true;
    };

    # Tools for secrets management
    environment.systemPackages = with pkgs; [sops age];

    # User config for manual sops editing (YubiKey, etc.). Only when an identity
    # is actually configured, since the homeManaged guard is applied once by
    # othrys.system.users and the condition here is the module's own.
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
