# modules/desktop/night-light.nix
# Screen color temperature (blue-light reduction) via gammastep
#
# Coordinates are identity-shaped, so the host provides them for the manual
# provider. A host that wants its location resolved instead turns geoclue on
# explicitly, since that enables a location service for the whole host.
# Noctalia hosts are excluded, since the shell has its own night light.
{
  config,
  lib,
  ...
}: let
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
      description = "Latitude for sunrise/sunset calculation. Identity-shaped, set from the consuming host together with longitude.";
    };

    longitude = lib.mkOption {
      type = lib.types.nullOr lib.types.float;
      default = null;
      example = -79.4;
      description = "Longitude for sunrise/sunset calculation, set together with latitude.";
    };

    geoclue.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Resolve the location through geoclue when no coordinates are set.
        This enables `services.geoclue2` for the whole host. With the nixpkgs
        defaults geoclue scans for nearby Wi-Fi networks, sends their
        hardware addresses to an online location service on every query, and
        answers any application that asks for the location. It is off by
        default for that reason, and a host with fixed coordinates does not
        need it.
      '';
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
        message = "othrys.desktop.nightLight: set latitude and longitude together.";
      }
      {
        assertion = manual || cfg.geoclue.enable;
        message = "othrys.desktop.nightLight needs a location: set latitude and longitude, or set othrys.desktop.nightLight.geoclue.enable to resolve it through geoclue.";
      }
    ];

    # Coordinates win when both are given, and geoclue then stays off.
    services.geoclue2.enable = lib.mkIf (!manual && cfg.geoclue.enable) true;

    othrys.internal.homeConfig."desktop.nightLight" = {
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
