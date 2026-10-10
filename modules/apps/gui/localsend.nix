# modules/apps/gui/localsend.nix
# LocalSend, local file sharing
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.localsend;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
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
    # The alias, the saved devices and the receive PIN live in the app's
    # share directory, and the app has no other state.
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        ".local/share/localsend_app"
      ];
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [53317];
      allowedUDPPorts = [53317];
    };

    othrys.internal.homeConfig."apps.localsend".home.packages = with pkgs; [localsend];
  };
}
