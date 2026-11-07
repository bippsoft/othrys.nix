# modules/system/locale.darwin.nix
# The nix-darwin implementation of othrys.system.locale
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.locale;
in {
  imports = [./locale.nix];

  # nix-darwin declares neither i18n nor console. LANG stands in for the
  # LC_* categories that locale.nixos.nix sets one by one, since each
  # category left unset falls back to LANG. The console options have no
  # meaning on macOS, which has no virtual console to set a font or keymap
  # on, and are read by nothing here.
  config = lib.mkIf cfg.enable {
    time.timeZone = cfg.timezone;
    environment.variables.LANG = cfg.locale;
  };
}
