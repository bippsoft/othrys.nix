# modules/hardware/ups.nix
# UPS monitoring and clean shutdown via NUT, in standalone mode where the UPS is
# attached to this host). Low-battery triggers the system shutdown, and power
# events push through othrys-notify when the notify module is enabled.
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.hardware.ups;
  notifyEnabled = config.othrys.services.notify.enable;

  notifyCmd = pkgs.writeShellScript "upsmon-notify" ''
    exec othrys-notify "UPS event on ${config.networking.hostName}" "$*"
  '';
in {
  # ANCHOR: ups-options
  options.othrys.hardware.ups = {
    enable = lib.mkEnableOption "UPS monitoring and clean shutdown (NUT, standalone)";

    driver = lib.mkOption {
      type = lib.types.str;
      default = "usbhid-ups";
      description = "NUT driver for the attached UPS (usbhid-ups covers most USB models).";
    };

    port = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = "Driver port ('auto' scans USB).";
    };

    passwordFile = lib.mkOption {
      type = othrysTypes.secretPath;
      example = lib.literalExpression ''config.sops.secrets."ups/password".path'';
      description = "Path to a runtime file holding the NUT monitor password (a secrets-provider path). Mandatory, with no default.";
    };
  };
  # ANCHOR_END: ups-options

  config = lib.mkIf cfg.enable {
    power.ups = {
      enable = true;
      mode = "standalone";

      ups.main = {
        inherit (cfg) driver port;
        description = "Local UPS.";
      };

      users.upsmon = {
        inherit (cfg) passwordFile;
        upsmon = "primary";
      };

      upsmon = {
        monitor.main = {
          system = "main@localhost";
          user = "upsmon";
          type = "primary";
        };
        settings = lib.mkIf notifyEnabled {
          NOTIFYCMD = "${notifyCmd}";
          NOTIFYFLAG = [
            ["ONBATT" "SYSLOG+EXEC"]
            ["ONLINE" "SYSLOG+EXEC"]
            ["LOWBATT" "SYSLOG+EXEC"]
            ["SHUTDOWN" "SYSLOG+EXEC"]
          ];
        };
      };
    };
  };
}
