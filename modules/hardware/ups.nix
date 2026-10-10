# modules/hardware/ups.nix
# UPS monitoring and clean shutdown through NUT, for a UPS attached to this host
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.hardware.ups;
  notifyCfg = config.othrys.services.notify;
  notifyEnabled = notifyCfg.enable;
  tokenStaged = notifyEnabled && notifyCfg.tokenFile != null;
  monitorUser = config.power.ups.upsmon.user;

  # upsmon starts as root and runs NOTIFYCMD from the child it drops to the
  # monitor user. The ntfy token is a root-only file, and a credential loaded
  # into this unit belongs to root as well, because the unit has no User= and
  # upsmon changes user by itself. The token is therefore loaded as a
  # credential and copied before start into a directory the monitor user owns,
  # which is how the NixOS module hands upsmon.conf its password.
  notifyCredentials = "/run/nut/othrys-notify";

  stageNotifyToken = pkgs.writeShellScript "upsmon-stage-notify-token" ''
    ${pkgs.coreutils}/bin/install -d -m0700 -o${monitorUser} ${notifyCredentials}
    ${pkgs.coreutils}/bin/install -m0400 -o${monitorUser} "$CREDENTIALS_DIRECTORY/token" ${notifyCredentials}/token
  '';

  # othrys-notify reads its token from $CREDENTIALS_DIRECTORY/token, so the
  # command points that variable at the staged copy.
  notifyCmd = pkgs.writeShellScript "upsmon-notify" ''
    ${lib.optionalString tokenStaged "export CREDENTIALS_DIRECTORY=${notifyCredentials}"}
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
    systemd.services.upsmon = lib.mkIf notifyEnabled {
      # A unit's PATH holds no system package, and othrys-notify is one.
      path = ["/run/current-system/sw"];
      serviceConfig = lib.mkIf tokenStaged {
        LoadCredential = ["token:${notifyCfg.tokenFile}"];
        ExecStartPre = ["${stageNotifyToken}"];
      };
    };

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
