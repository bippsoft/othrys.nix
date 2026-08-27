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
  options.othrys.services.printing = {
    enable = lib.mkEnableOption "CUPS printing service";

    avahi = lib.mkEnableOption "Avahi for network printer discovery";
  };

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
      drivers = with pkgs; [gutenprint];
    };

    # Network printer discovery
    services.avahi = lib.mkIf cfg.avahi {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    # Printer configuration GUI only on desktop hosts. Headless print
    # servers administer CUPS via its web UI on :631.
    environment.systemPackages = lib.optionals config.othrys.desktop.graphical (with pkgs; [
      system-config-printer
    ]);
  };
}
