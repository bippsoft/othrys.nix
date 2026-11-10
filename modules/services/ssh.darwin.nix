# modules/services/ssh.darwin.nix
# The nix-darwin implementation of othrys.services.ssh
#
# ssh.nix writes the known hosts and the user's client configuration. The
# server is the macOS Remote Login service, and nix-darwin's
# services.openssh turns it on and takes sshd_config text in place of
# settings, so the hardened defaults in ../lib/sshd.nix are rendered into
# it. launchd starts that sshd on port 22, and the firewall nix-darwin
# manages filters by application with no port list, so the port list is
# checked and openFirewall is left unread.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.services.ssh;
  sshd = import ../lib/sshd.nix {inherit lib;};

  # Apple ships its own OpenSSH build with each macOS release, and one
  # older than 9.9 refuses the whole KexAlgorithms line over an algorithm
  # it does not know. The other post-quantum exchange, sntrup761, is in
  # every release since 8.5, so mlkem768 is left out here.
  settings =
    sshd.settings
    // {
      KexAlgorithms = lib.remove "mlkem768x25519-sha256" sshd.settings.KexAlgorithms;
    };
in {
  imports = [./ssh.nix];

  config = lib.mkIf (cfg.enable && cfg.server.enable) {
    assertions = [
      {
        assertion = cfg.server.ports == [22];
        message = "othrys.services.ssh.server.ports is ${builtins.toJSON cfg.server.ports}, and the macOS Remote Login service that nix-darwin turns on listens on port 22 alone, since launchd owns the socket. Leave the ports at [22] on a darwin host.";
      }
    ];

    services.openssh = {
      enable = true;
      # sshd keeps the first value it reads for a directive, and the
      # sshd_config macOS ships includes this directory at its top, so the
      # lines here win over Apple's defaults. A host adds its own lines to
      # services.openssh.extraConfig, ahead of these with lib.mkBefore.
      extraConfig = sshd.render settings;
    };

    # A login from Ghostty or kitty sets TERM to xterm-ghostty or
    # xterm-kitty, and the terminfo database macOS ships has neither, so
    # clear, backspace and full-screen programs break in the session.
    # nix-darwin links share/terminfo from the system path and puts it on
    # TERMINFO_DIRS. Only the two terminals othrys ships are named, since
    # environment.enableAllTerminfo pulls the terminfo output of eleven
    # terminals, several of which a Mac would otherwise build from source.
    environment.systemPackages = [
      pkgs.ghostty-bin.terminfo
      pkgs.kitty.terminfo
    ];
  };
}
