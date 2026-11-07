# modules/apps/gui/vesktop.nix
# Vesktop - Discord client with Wayland support
{
  lib,
  pkgs,
  ...
}: {
  options.othrys.apps.vesktop = {
    enable = lib.mkEnableOption "Vesktop Discord client";

    settings = lib.mkOption {
      # The value is written with builtins.toJSON, so it is held to what JSON
      # can carry. A function or a package is refused here by name, where
      # toJSON would abort or write a store path into the file.
      type = lib.types.attrsOf (pkgs.formats.json {}).type;
      default = {};
      description = "Extra Vesktop settings.json values, merged over the module defaults (override any default by re-declaring its key). Any JSON value is accepted.";
      example = lib.literalExpression "{ startMinimized = true; }";
    };
  };
}
