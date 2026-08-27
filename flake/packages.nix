# flake/packages.nix
# Packaged scripts and tools exposed as flake outputs
_: {
  perSystem = {pkgs, ...}: {
    packages = {
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
        ];

        text = builtins.readFile ../scripts/yubikey-onboard.sh;
      };
    };
  };
}
