# What this host wants from othrys. Every module is off until enabled here.
{
  networking.hostName = "myhost";

  # The primary user. There is no default, and a headless host that enables no
  # per-user feature can leave this and the block below out.
  othrys.system.user.name = "alice";
  othrys.system.users = {
    enable = true;
    # The bootstrap password, as a `mkpasswd -m yescrypt` hash. It lands in
    # the world-readable Nix store, so treat it as public and replace it once
    # a secrets provider decrypts on boot. The replacement is a runtime path
    # that exists before the users activation step; with sops-nix that is a
    # secret declared with `neededForUsers = true`:
    #
    #   sops.secrets."users/alice/password".neededForUsers = true;
    #   othrys.system.users.passwordFile =
    #     config.sops.secrets."users/alice/password".path;
    #
    # A path under /run/secrets/ is installed after the account is created
    # and leaves it with no usable password.
    initialHashedPassword = "$y$j9T$REPLACE-WITH-YOUR-OWN-HASH";
  };

  othrys.system.nix = {
    enable = true;
    # Mandatory. The release this host was first installed at, never bumped
    # afterwards.
    stateVersion = "26.05";
    # Licensing is your policy, so this defaults to false.
    allowUnfree = false;
  };

  othrys.system.bootloader.enable = true;
  othrys.system.locale.enable = true;

  # sshd accepts keys only, so a host reached over the network needs one here
  # or the console is the only way in.
  othrys.services.ssh = {
    enable = true;
    server.enable = true;
  };
  users.users.alice.openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAA... alice@example.com"
  ];
}
