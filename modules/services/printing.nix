# modules/services/printing.nix
# CUPS printing service
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.services.printing;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  # ANCHOR: printing-options
  options.othrys.services.printing = {
    enable = lib.mkEnableOption "CUPS printing service";

    avahi = lib.mkEnableOption "Avahi for network printer discovery";

    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["localhost:631"];
      example = ["*:631"];
      description = ''
        Addresses and ports CUPS listens on (services.printing.listenAddresses).
        The default is loopback only. A print server reached from other
        hosts lists an address here and also sets
        `services.printing.allowFrom`, which stays at upstream's `localhost`.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the TCP ports named in `listenAddresses` in the firewall (services.printing.openFirewall).";
    };
  };
  # ANCHOR_END: printing-options

  config = lib.mkIf cfg.enable {
    # Persistence for printer configuration
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/cups";
          user = "root";
          group = "root";
          mode = "0755";
        }
      ];
    };

    services.printing = {
      enable = true;
      inherit (cfg) listenAddresses openFirewall;
      drivers = with pkgs; [gutenprint];
    };

    # Network printer discovery
    services.avahi = lib.mkIf cfg.avahi {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Printer configuration GUI only on desktop hosts. A headless print
    # server is administered through the CUPS web UI on :631, which answers
    # on loopback until listenAddresses names another address.
    environment.systemPackages = lib.optionals config.othrys.desktop.graphical (with pkgs; [
      system-config-printer
    ]);
  };
}
