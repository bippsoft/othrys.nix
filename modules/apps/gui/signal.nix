# modules/apps/gui/signal.nix
# Signal Desktop messenger
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.signal;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.signal = {
    enable = lib.mkEnableOption "Signal Desktop messenger";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/Signal"
      ];
    };

    othrys.internal.homeConfig."apps.signal" = {
      home.packages = with pkgs; [signal-desktop];
    };
  };
}
