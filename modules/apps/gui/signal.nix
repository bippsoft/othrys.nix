# modules/apps/gui/signal.nix
# Signal Desktop messenger
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.signal;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.signal = {
    enable = lib.mkEnableOption "Signal Desktop messenger";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      # config.json carries the database key, and the directory holds the
      # message database, the attachments and the linked-device identity.
      users.${username}.directories = [
        {
          directory = ".config/Signal";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.signal" = {
      home.packages = with pkgs; [signal-desktop];
    };
  };
}
