# modules/system/locale.nixos.nix
# The NixOS implementation of othrys.system.locale
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.locale;
in {
  imports = [./locale.nix];

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
