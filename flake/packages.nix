# flake/packages.nix
# Packaged scripts and tools exposed as flake outputs
_: {
  perSystem = {
    lib,
    pkgs,
    ...
  }: {
    # The onboarding script needs unshare, findmnt and the util-linux mount,
    # which exist on Linux alone, so a darwin system has no such package.
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      yubikey-onboard = pkgs.writeShellApplication {
        name = "yubikey-onboard";

        runtimeInputs = with pkgs; [
          gnupg
          yubikey-manager
          pam_u2f
          age-plugin-yubikey
          ssh-to-age
          pinentry-curses
          openssh
          coreutils
          gawk
          gnugrep
          gnused
          diffutils
          # The backup is encrypted and decrypted with age itself. The plugin
          # package holds only the YubiKey recipient type.
          age
          # unshare, findmnt, and a mount that is not the setuid wrapper, which
          # is the one that works for the root of a user namespace.
          util-linux
        ];

        text = builtins.readFile ../scripts/yubikey-onboard.sh;
      };
    };
  };
}
