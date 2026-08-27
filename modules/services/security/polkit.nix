# modules/services/security/polkit.nix
# Polkit privilege escalation
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.security.polkit;
in {
  options.othrys.services.security.polkit = {
    enable = lib.mkEnableOption "Polkit privilege escalation";
  };

  config = lib.mkIf cfg.enable {
    security.polkit.enable = true;
  };
}
