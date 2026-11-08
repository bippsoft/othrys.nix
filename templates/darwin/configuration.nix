# What this Mac wants from othrys. Every module is off until enabled here.
{
  networking.hostName = "mymac";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # nix-darwin's own state version, an integer, set once at the first
  # switch and never bumped afterwards.
  system.stateVersion = 6;

  # The administrator account macOS created at setup. othrys makes it the
  # primary user and leaves Home Manager managing it, while the account
  # itself stays with macOS. othrys.system.users.uid stays unset for it,
  # since nix-darwin must not manage the administrator account.
  othrys.system.user.name = "alice";
  othrys.system.users.enable = true;

  othrys.system.nix = {
    enable = true;
    # Mandatory. The Home Manager state version, the release this host was
    # first switched at, never bumped afterwards.
    stateVersion = "26.05";
    # Licensing is your policy, so this defaults to false.
    allowUnfree = false;
  };

  othrys.system.locale.enable = true;
  othrys.system.shell.zsh.enable = true;
  othrys.services.ssh.enable = true;
}
