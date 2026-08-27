# modules/apps/gui/rustdesk.nix
# RustDesk remote desktop client
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.apps.rustdesk;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.rustdesk = {
    enable = lib.mkEnableOption "RustDesk remote desktop client";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open TCP 21118, which the client listens on for direct IP access.
        Only needed when peers connect to this host by address instead of
        through a rendezvous server, so it stays off by default.

        This module installs the client. A rendezvous and relay server is
        `services.rustdesk-server`, which othrys does not wrap, and its ports
        are not opened here.
      '';
    };
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

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [21118];
    };

    home-manager.users = lib.mkIf hmEnabled {
      ${username}.home.packages = with pkgs; [rustdesk];
    };
  };
}
