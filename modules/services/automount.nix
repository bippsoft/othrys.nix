# modules/services/automount.nix
# USB automounting service (user-level)
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.services.automount;
  desktopEnabled = config.othrys.desktop.graphical;
in {
  options.othrys.services.automount = {
    enable = lib.mkEnableOption "USB automounting via udiskie";

    notify = lib.mkOption {
      type = lib.types.bool;
      default = desktopEnabled;
      defaultText = lib.literalExpression "config.othrys.desktop.graphical";
      description = "Show mount/unmount notifications (needs a notification daemon; off on headless hosts).";
    };

    tray = lib.mkOption {
      type = lib.types.enum ["auto" "always" "never"];
      default =
        if desktopEnabled
        then "auto"
        else "never";
      defaultText = lib.literalExpression ''"auto" on graphical hosts (othrys.desktop.graphical), "never" otherwise'';
      description = "udiskie tray icon mode (needs a StatusNotifier host; off on headless hosts).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Automounting requires udisks2
    services.udisks2.enable = true;

    # udiskie is a per-user agent, enabled only when othrys manages the user account
    # (see modules/system/nix.nix for the guard rationale).
    home-manager.users = lib.mkIf hmEnabled {
      ${username}.services.udiskie = {
        enable = true;
        automount = true;
        inherit (cfg) notify tray;
      };
    };
  };
}
