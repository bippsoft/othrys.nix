# modules/system/secrets.darwin.nix
# The nix-darwin implementation of othrys.system.secrets
#
# Exported as darwinModules.secrets and left out of darwinModules.default, so
# a host imports it together with the sops-nix darwin module or imports
# neither. sops-nix on darwin decrypts with the ssh host keys of
# services.openssh by default, and a Mac may have none, so this file takes
# no ssh key and generates an age key at the path the host names.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.secrets;
in {
  imports = [./secrets.nix];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.sops.age.keyFile != null || config.sops.age.sshKeyPaths != [] || config.sops.gnupg.home != null;
        message = "othrys.system.secrets on nix-darwin takes no ssh host key, so sops-nix has no key to decrypt with. Set sops.age.keyFile to the path of an age key, for example \"/var/lib/sops-nix/key.txt\", or name an ssh key in sops.age.sshKeyPaths or a GnuPG home in sops.gnupg.home.";
      }
    ];

    # mkDefault, so a host that does keep an ssh host key adds it without
    # mkForce. The age key is generated at sops.age.keyFile on the first
    # activation, as on NixOS.
    sops.age.sshKeyPaths = lib.mkDefault [];
    sops.gnupg.sshKeyPaths = lib.mkDefault [];
    sops.age.generateKey = lib.mkDefault true;

    environment.systemPackages = with pkgs; [sops age];
  };
}
