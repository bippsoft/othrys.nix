# modules/apps/gui/localsend.nix
# LocalSend, local file sharing
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.apps.localsend;
in {
  options.othrys.apps.localsend = {
    enable = lib.mkEnableOption "LocalSend file sharing";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open TCP and UDP 53317, which LocalSend uses for peer discovery and
        transfers. Unlike most othrys firewall toggles this defaults to true,
        since a LocalSend host that other devices cannot reach does nothing at
        all. Set it to false on a host that only sends.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [53317];
      allowedUDPPorts = [53317];
    };

    home-manager.users = lib.mkIf hmEnabled {
      ${username}.home.packages = with pkgs; [localsend];
    };
  };
}
