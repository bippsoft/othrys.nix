# modules/theme/stylix.nix
# Options of the Stylix adapter, which configures Stylix from othrys.theme
{
  config,
  lib,
  ...
}: {
  imports = [
    (lib.mkRenamedOptionModule ["othrys" "system" "stylix" "scheme"] ["othrys" "theme" "scheme"])
    (lib.mkRenamedOptionModule ["othrys" "system" "stylix" "polarity"] ["othrys" "theme" "polarity"])
    (lib.mkRenamedOptionModule ["othrys" "system" "stylix" "wallpaper"] ["othrys" "theme" "wallpaper" "source"])
  ];

  options.othrys.system.stylix = {
    enable = lib.mkEnableOption "Stylix system-wide theming, configured from `othrys.theme`";

    gui.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.othrys.desktop.graphical;
      defaultText = lib.literalExpression "config.othrys.desktop.graphical";
      description = ''
        Theme the graphical surface too: curated fonts, cursor, GTK, and
        per-user icon/cursor config. Off, Stylix still themes the console and
        Plymouth (the headless-relevant targets) without dragging the GUI
        font/cursor/GTK closure onto servers.
      '';
    };
  };
}
