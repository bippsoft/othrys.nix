# modules/system/locale.nix
# Regional settings: locale, timezone, console
{lib, ...}: {
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
}
