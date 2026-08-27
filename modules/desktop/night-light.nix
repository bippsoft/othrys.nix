# modules/desktop/night-light.nix
# Screen color temperature (blue-light reduction) via gammastep. Coordinates
# are identity-shaped, so the host provides them for the manual provider, and
# without them, geoclue resolves location automatically. Noctalia hosts are
# excluded, since the shell has its own night light.
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.desktop.nightLight;
  manual = cfg.latitude != null && cfg.longitude != null;
in {
  # ANCHOR: night-light-options
  options.othrys.desktop.nightLight = {
    enable = lib.mkEnableOption "night light (color temperature shifting) via gammastep";

    temperature = {
      day = lib.mkOption {
        type = lib.types.ints.positive;
        default = 6500;
        description = "Daytime color temperature in Kelvin.";
      };
      night = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4000;
        description = "Nighttime color temperature in Kelvin.";
      };
    };

    latitude = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      example = 43.7;
      description = "Latitude for sunrise/sunset calculation. Identity-shaped, set from the consuming host. With longitude also null it falls back to geoclue.";
    };

    longitude = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      example = -79.4;
      description = "Longitude for sunrise/sunset calculation; null (with latitude null) falls back to geoclue.";
    };
  };
  # ANCHOR_END: night-light-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.othrys.desktop.graphical;
        message = "othrys.desktop.nightLight requires a graphical session: enable a compositor module (or set othrys.desktop.graphical for an unmanaged one).";
      }
      {
        assertion = !config.othrys.desktop.noctalia.enable;
        message = "othrys.desktop.nightLight conflicts with othrys.desktop.noctalia, which has a built-in night light.";
      }
      {
        assertion = (cfg.latitude == null) == (cfg.longitude == null);
        message = "othrys.desktop.nightLight: set latitude and longitude together (or neither, for geoclue).";
      }
    ];

    # geoclue is only needed when no manual coordinates are provided.
    services.geoclue2.enable = lib.mkIf (!manual) true;

    home-manager.users.${username} = {
      services.gammastep = {
        enable = true;
        provider =
          if manual
          then "manual"
          else "geoclue2";
        inherit (cfg) latitude longitude;
        temperature = {
          inherit (cfg.temperature) day night;
        };
      };
    };
  };
}
