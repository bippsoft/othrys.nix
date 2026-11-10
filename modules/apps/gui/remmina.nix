# modules/apps/gui/remmina.nix
# Remmina remote desktop client, for VNC, RDP, SPICE and SSH
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.remmina;
in {
  # ANCHOR: remmina-options
  options.othrys.apps.remmina = {
    enable = lib.mkEnableOption "Remmina remote desktop client";
  };
  # ANCHOR_END: remmina-options

  config = lib.mkIf cfg.enable {
    # Profiles live in ~/.local/share/remmina and the preferences in
    # ~/.config/remmina/remmina.pref. With no Secret Service running, Remmina
    # encrypts a saved password into the profile with a key taken from the
    # `secret` in remmina.pref, so losing that file makes every saved password
    # unreadable, and anyone reading both directories can decrypt them. Both
    # are persisted at 0700.
    othrys.internal.persist."apps.remmina" = {
      user.directories = [
        {
          directory = ".config/remmina";
          mode = "0700";
        }
        {
          directory = ".local/share/remmina";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.remmina".services.remmina = {
      enable = true;
      # Home Manager otherwise starts `remmina --icon` as a user service at
      # every login, which keeps a tray icon and a process running on a host
      # that opens a connection now and then.
      systemdService.enable = lib.mkDefault false;
    };
  };
}
