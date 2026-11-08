# modules/services/security/yubikey.darwin.nix
# The nix-darwin implementation of othrys.services.security.yubikey
#
# yubikey.nix writes the user's GnuPG configuration and the gpg-agent that
# Home Manager runs as a launchd agent, with pinentry-mac for the PIN on a
# host that keeps othrys.desktop.graphical on.
# macOS reads the token through its own smart card stack, so there is no
# pcscd or udev to set up. The U2F login of the NixOS side is not carried
# over, and Touch ID for sudo stays the host's own choice, since it lets a
# fingerprint alone pass sudo while u2fRequirePassword defaults to two
# factors.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.services.security.yubikey;
in {
  imports = [./yubikey.nix];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.u2fMappings == {};
        message = "othrys.services.security.yubikey.u2fMappings is set on a darwin host, and the module writes no pam_u2f line on nix-darwin. Leave it empty there.";
      }
    ];

    # pam_u2f is left out, since it only generates mappings for the PAM
    # side that this platform does not have.
    environment.systemPackages = with pkgs; [
      gnupg
      age-plugin-yubikey
      ssh-to-age
      yubikey-personalization
      yubikey-manager
    ];
  };
}
