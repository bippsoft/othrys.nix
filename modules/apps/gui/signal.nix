# modules/apps/gui/signal.nix
# Signal Desktop messenger
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.signal;
in {
  options.othrys.apps.signal = {
    enable = lib.mkEnableOption "Signal Desktop messenger";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.persist."apps.signal" = {
      # config.json carries the database key, and the directory holds the
      # message database, the attachments and the linked-device identity.
      user.directories = [
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
