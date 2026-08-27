# modules/apps/gui/rustdesk.nix
# RustDesk remote desktop
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.rustdesk;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.rustdesk = {
    enable = lib.mkEnableOption "RustDesk remote desktop";
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/rustdesk";
          user = "root";
          group = "root";
          mode = "0755";
        }
      ];
    };

    networking.firewall = {
      allowedTCPPorts = [21114 21115 21116 21117 21118 21119];
      allowedUDPPorts = [21116];
    };

    home-manager.users.${username} = {
      home.packages = with pkgs; [rustdesk];
    };
  };
}
