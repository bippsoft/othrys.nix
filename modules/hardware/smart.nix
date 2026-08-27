# modules/hardware/smart.nix
# Disk health monitoring via smartd (auto-detected devices). SMART warnings
# reach the wall by default. With othrys.services.notify enabled they are
# also pushed through othrys-notify (smartd's mailer hook, no mail stack).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.hardware.smart;
  notifyEnabled = config.othrys.services.notify.enable;

  # smartd pipes the warning message to the "mailer" on stdin.
  notifyMailer = pkgs.writeShellScript "smartd-notify" ''
    message="$(cat)"
    exec othrys-notify "SMART warning on ${config.networking.hostName}" "$message"
  '';
in {
  # ANCHOR: smart-options
  options.othrys.hardware.smart = {
    enable = lib.mkEnableOption "disk health monitoring (smartd, auto-detected devices)";

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra options passed to smartd.";
    };
  };
  # ANCHOR_END: smart-options

  config = lib.mkIf cfg.enable {
    services.smartd = {
      enable = true;
      autodetect = true;
      inherit (cfg) extraOptions;

      notifications = {
        wall.enable = true;
        mail = lib.mkIf notifyEnabled {
          enable = true;
          recipient = "root";
          mailer = notifyMailer;
        };
      };
    };
  };
}
