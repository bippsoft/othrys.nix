# flake/checks/traefik.nix
# CORE. The Traefik TLS floor and security headers, read back from the
# configuration the module hands to services.traefik. One host takes every
# default with ACME on, one turns each default off, and one overrides a
# generated value through dynamicConfigOptions, which has to win.
{
  hostConfig,
  mkExpectations,
  bootBase,
}: let
  traefikHost = traefik:
    (hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
        othrys.services.traefik = {enable = true;} // traefik;
      }
    ]).services.traefik;

  acme = {
    enable = true;
    email = "alice@example.com";
    dnsProvider = "cloudflare";
  };

  defaults = traefikHost {
    inherit acme;
    environmentFiles = ["/run/secrets/traefik-env"];
  };
  noAcme = traefikHost {};
  allOff = traefikHost {
    tls = {
      minVersion = null;
      sniStrict = false;
    };
    securityHeaders = {
      hstsSeconds = 0;
      contentTypeNosniff = false;
      frameOptions = null;
    };
  };
  overridden = traefikHost {
    dynamicConfigOptions = {
      tls.options.default.minVersion = "VersionTLS13";
      http.routers.app.rule = "Host(`app.example.com`)";
    };
  };

  middleware = "othrys-security-headers";
  headersOf = host: host.dynamicConfigOptions.http.middlewares.${middleware}.headers;
  attached = host: host.staticConfigOptions.entryPoints.websecure.http.middlewares or [];
in
  mkExpectations "othrys-eval-traefik" {
    "the default TLS floor is 1.2" = defaults.dynamicConfigOptions.tls.options.default.minVersion == "VersionTLS12";
    "sniStrict is on with ACME" = defaults.dynamicConfigOptions.tls.options.default.sniStrict;
    "sniStrict is off without ACME" = !noAcme.dynamicConfigOptions.tls.options.default.sniStrict;
    "HSTS defaults to one year" = (headersOf defaults).stsSeconds == 31536000;
    "HSTS leaves subdomains and preload alone" = !((headersOf defaults) ? stsIncludeSubdomains) && !((headersOf defaults) ? stsPreload);
    "nosniff is on" = (headersOf defaults).contentTypeNosniff;
    "frames are limited to the same origin" = (headersOf defaults).customFrameOptionsValue == "SAMEORIGIN";
    "the middleware is attached at websecure" = attached defaults == ["${middleware}@file"];
    "the ACME resolver survives next to the middleware" = defaults.staticConfigOptions.entryPoints.websecure.http.tls.certResolver == "letsencrypt";
    "minVersion = null leaves Traefik's default" = !(allOff.dynamicConfigOptions.tls.options.default ? minVersion);
    "sniStrict can be turned off" = !allOff.dynamicConfigOptions.tls.options.default.sniStrict;
    "with every header off no middleware is defined" = !(allOff.dynamicConfigOptions ? http);
    "with every header off nothing is attached" = attached allOff == [];
    "dynamicConfigOptions overrides a generated value" = overridden.dynamicConfigOptions.tls.options.default.minVersion == "VersionTLS13";
    "dynamicConfigOptions keeps the generated middleware" = (headersOf overridden).contentTypeNosniff;
    "dynamicConfigOptions adds its own router" = overridden.dynamicConfigOptions.http.routers.app.rule == "Host(`app.example.com`)";
  }
