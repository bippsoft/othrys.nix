# modules/services/security/sudo.nix
# Sudo configuration
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.security.sudo;
in {
  options.othrys.services.security.sudo = {
    enable = lib.mkEnableOption "Sudo configuration";

    execWheelOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Only allow users in the wheel group to run sudo at all.";
    };
  };

  config = lib.mkIf cfg.enable {
    security.sudo = {
      enable = true;
      wheelNeedsPassword = true;
      inherit (cfg) execWheelOnly;
    };
  };
}
