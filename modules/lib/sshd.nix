# modules/lib/sshd.nix
# The hardened sshd settings both platforms of othrys.services.ssh write
#
# Imported directly like types.nix. NixOS takes the attrset as
# services.openssh.settings, each value a default, and nix-darwin renders
# it into the sshd_config text it writes, since its services.openssh has
# no settings option.
{lib}: {
  settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    X11Forwarding = false;

    # PAM stays on. With password and keyboard-interactive login off it
    # authenticates nobody, and sshd still runs the account and session
    # stacks through it, which is what opens the systemd-logind session
    # and applies limits. A host that puts pam_u2f into the sshd service
    # needs it as well.
    UsePAM = true;

    # Forwarding turns a login into a tunnel into the host's network and
    # hands the client's agent to anyone with root on the host. A host
    # that is a jump host or serves remote editors turns these back on.
    AllowTcpForwarding = "no";
    AllowAgentForwarding = "no";

    MaxAuthTries = 3;
    LoginGraceTime = 30;
    MaxSessions = 4;
    # A client that answers no keepalive for ten minutes is disconnected.
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;

    # VERBOSE logs the fingerprint of the key behind every login, and it
    # is the level the fail2ban sshd filter reads.
    LogLevel = "VERBOSE";

    # Explicit lists, narrower than the set nixpkgs recommends. They drop
    # the finite-field group exchange, the 128 and 192 bit CTR ciphers and
    # umac. Every client since OpenSSH 6.5 supports curve25519 with
    # chacha20-poly1305, while an older one needs an entry added back.
    KexAlgorithms = [
      "sntrup761x25519-sha512@openssh.com"
      "mlkem768x25519-sha256"
      "curve25519-sha256"
      "curve25519-sha256@libssh.org"
    ];
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
      "aes256-ctr"
    ];
    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
    ];
  };

  # One sshd_config line per setting, in the form sshd reads. A list is
  # joined with commas and a boolean is yes or no.
  render = attrs:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name} ${
        if builtins.isList value
        then lib.concatStringsSep "," value
        else if value == true
        then "yes"
        else if value == false
        then "no"
        else toString value
      }")
      attrs);
}
