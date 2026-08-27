# modules/apps/gui/localsend.nix
# LocalSend, local file sharing
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.localsend;
in {
  options.othrys.apps.localsend = {
    enable = lib.mkEnableOption "LocalSend file sharing";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [53317];
    networking.firewall.allowedUDPPorts = [53317];

    home-manager.users.${username} = {
      home.packages = with pkgs; [localsend];
    };
  };
}
