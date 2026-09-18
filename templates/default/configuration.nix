# What this host wants from othrys. Every module is off until enabled here.
{
  networking.hostName = "myhost";

  # The primary user. There is no default, and a headless host that enables no
  # per-user feature can leave this and the block below out.
  othrys.system.user.name = "alice";
  othrys.system.users = {
    enable = true;
    # A runtime path written by your secrets provider, so nothing reaches the
    # Nix store. To bring a host up before secrets decrypt, set
    # initialHashedPassword to a `mkpasswd -m yescrypt` hash instead and move
    # to passwordFile afterwards.
    passwordFile = "/run/secrets/users/alice/password";
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

  othrys.services.ssh = {
    enable = true;
    server.enable = true;
  };
}
