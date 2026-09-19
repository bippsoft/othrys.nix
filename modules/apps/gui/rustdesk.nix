# modules/apps/gui/rustdesk.nix
# RustDesk remote desktop client
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
    # The client keeps its id, its key pair, its permanent password, its
    # options and its saved peers under ~/.config/rustdesk, and nothing under
    # /var/lib. Without this every boot produced a new id and an empty address
    # book. 0700 because of the key pair and the password. The logs under
    # ~/.local/share/logs/RustDesk are left on the ephemeral root.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        {
          directory = ".config/rustdesk";
          mode = "0700";
        }
      ];
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [21118];
    };

    othrys.internal.homeConfig."apps.rustdesk" = {
      home.packages = with pkgs; [rustdesk];
    };
  };
}
