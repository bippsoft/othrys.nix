# modules/services/firewall.nix
# Base firewall configuration
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.firewall;
in {
  options.othrys.services.firewall = {
    enable = lib.mkEnableOption "Base firewall";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = {
      enable = true;
    };
  };
}
