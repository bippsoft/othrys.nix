# modules/desktop/uwsm.nix
# UWSM - Universal Wayland Session Manager for systemd integration.
# The login manager lives in login.nix.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.desktop.uwsm;
in {
  options.othrys.desktop.uwsm = {
    enable = lib.mkEnableOption "UWSM Wayland session management";
  };

  config = lib.mkIf cfg.enable {
    # Manage Wayland compositors as systemd units.
    programs.uwsm.enable = true;

    # Electron apps use Wayland natively.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };
}
