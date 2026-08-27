# modules/system/locale.nix
# Regional settings: locale, timezone, console
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.locale;
in {
  options.othrys.system.locale = {
    enable = lib.mkEnableOption "Locale and regional settings";

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      example = "America/New_York";
      description = "System timezone.";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      description = "System locale.";
    };

    console = {
      font = lib.mkOption {
        type = lib.types.str;
        default = "Lat2-Terminus16";
        description = "Console font.";
      };

      keyMap = lib.mkOption {
        type = lib.types.str;
        default = "us";
        description = "Console keyboard layout.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    i18n.defaultLocale = cfg.locale;

    i18n.extraLocaleSettings = {
      LC_ADDRESS = cfg.locale;
      LC_IDENTIFICATION = cfg.locale;
      LC_MEASUREMENT = cfg.locale;
      LC_MONETARY = cfg.locale;
      LC_NAME = cfg.locale;
      LC_NUMERIC = cfg.locale;
      LC_PAPER = cfg.locale;
      LC_TELEPHONE = cfg.locale;
      LC_TIME = cfg.locale;
    };

    console = {
      inherit (cfg.console) font keyMap;
    };

    time.timeZone = cfg.timezone;
  };
}
