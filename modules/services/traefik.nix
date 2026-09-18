# modules/services/traefik.nix
# Traefik, a reverse proxy and edge router with automatic TLS (DNS-01 ACME)
{
  config,
  lib,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.traefik;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  acmeStorage =
    if cfg.acme.storage != null
    then cfg.acme.storage
    else "${cfg.dataDir}/acme.json";

  # Static config assembled from the options, and hosts extend it via
  # staticConfigOptions (merged on top).
  generatedStatic =
    {
      entryPoints = {
        web =
          {address = ":80";}
          // lib.optionalAttrs cfg.httpsRedirect {
            http.redirections.entryPoint = {
              to = "websecure";
              scheme = "https";
            };
          };
        websecure =
          lib.recursiveUpdate (
            {address = ":443";}
            // lib.optionalAttrs cfg.acme.enable {
              http.tls.certResolver = cfg.acme.resolver;
            }
          ) (lib.optionalAttrs headersOn {
            # Attached at the entrypoint so every router behind it gets the
            # headers without naming the middleware itself.
            http.middlewares = ["${headersMiddleware}@file"];
          });
      };
    }
    // lib.optionalAttrs cfg.dashboard.enable {
      api = {
        dashboard = true;
        inherit (cfg.dashboard) insecure;
      };
    }
    // lib.optionalAttrs cfg.acme.enable {
      certificatesResolvers.${cfg.acme.resolver}.acme = {
        email = cfg.acme.email;
        storage = acmeStorage;
        dnsChallenge =
          {provider = cfg.acme.dnsProvider;}
          // lib.optionalAttrs (cfg.acme.dnsResolvers != []) {
            resolvers = cfg.acme.dnsResolvers;
          };
      };
    };

  headersMiddleware = "othrys-security-headers";
  headers =
    lib.optionalAttrs (cfg.securityHeaders.hstsSeconds > 0) {
      stsSeconds = cfg.securityHeaders.hstsSeconds;
    }
    // lib.optionalAttrs cfg.securityHeaders.contentTypeNosniff {
      contentTypeNosniff = true;
    }
    // lib.optionalAttrs (cfg.securityHeaders.frameOptions != null) {
      customFrameOptionsValue = cfg.securityHeaders.frameOptions;
    };
  headersOn = cfg.securityHeaders.enable && headers != {};

  # Dynamic config assembled from the options. dynamicConfigOptions is merged
  # on top, so a host can replace any value here, tls.options.default included.
  generatedDynamic =
    {
      tls.options.default =
        {inherit (cfg.tls) sniStrict;}
        // lib.optionalAttrs (cfg.tls.minVersion != null) {
          inherit (cfg.tls) minVersion;
        };
    }
    // lib.optionalAttrs headersOn {
      http.middlewares.${headersMiddleware}.headers = headers;
    };
in {
  # ANCHOR: traefik-options
  options.othrys.services.traefik = {
    enable = lib.mkEnableOption "Traefik reverse proxy";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/traefik";
      description = "Persistent data directory (holds acme.json).";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "traefik";
      description = "Group Traefik runs under (set to \"docker\" for the Docker provider).";
    };

    httpsRedirect = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Redirect the web (:80) entrypoint to websecure (:443).";
    };

    dashboard = {
      enable = lib.mkEnableOption "the Traefik dashboard/API";

      insecure = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Expose the dashboard on :8080 without auth. Convenient but unsafe, so prefer a secured router.";
      };
    };

    acme = {
      enable = lib.mkEnableOption "automatic TLS via Let's Encrypt (DNS-01)";

      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Contact email for the ACME account.";
      };

      dnsProvider = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "cloudflare";
        description = "lego DNS provider name. Its credentials are supplied via environmentFiles.";
      };

      resolver = lib.mkOption {
        type = lib.types.str;
        default = "letsencrypt";
        description = "Name of the certificate resolver referenced by routers.";
      };

      dnsResolvers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["1.1.1.1:53" "8.8.8.8:53"];
        description = "DNS servers used to check record propagation.";
      };

      storage = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to acme.json. Defaults to <dataDir>/acme.json.";
      };
    };

    tls = {
      minVersion = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum ["VersionTLS12" "VersionTLS13"]);
        default = "VersionTLS12";
        description = ''
          Lowest TLS version the default TLS options accept. Traefik's own
          default admits TLS 1.0 and 1.1. `null` leaves Traefik's default in
          place.
        '';
      };

      sniStrict = lib.mkOption {
        type = lib.types.bool;
        default = cfg.acme.enable;
        defaultText = lib.literalExpression "config.othrys.services.traefik.acme.enable";
        description = ''
          Refuse a TLS connection whose server name matches no certificate,
          instead of answering with Traefik's self-signed default certificate.
          A request made to the bare IP address is refused as well.

          On by default when ACME issues the certificates, since every routed
          host then has one. Off by default otherwise, because a proxy with no
          certificate of its own would refuse every connection.
        '';
      };
    };

    securityHeaders = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Attach a headers middleware to the websecure entrypoint, so every
          router behind it sends the headers below. A router that needs
          different values sets its own headers middleware, which runs after
          this one and wins. Set to `false` to attach nothing.
        '';
      };

      hstsSeconds = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 31536000;
        description = ''
          `max-age` of the `Strict-Transport-Security` header, one year by
          default. Subdomains are not included and preload is not requested,
          since both reach past the hosts this proxy serves. `0` sends no HSTS
          header.
        '';
      };

      contentTypeNosniff = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Send `X-Content-Type-Options: nosniff`.";
      };

      frameOptions = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "SAMEORIGIN";
        example = "DENY";
        description = ''
          Value of the `X-Frame-Options` header. The default lets a site frame
          its own pages and stops other origins from framing them, which breaks
          a dashboard embedded from a different host name. `null` sends no such
          header.
        '';
      };
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf othrysTypes.secretPath;
      default = [];
      example = lib.literalExpression ''[ config.sops.secrets."traefik/env".path ]'';
      description = ''
        EnvironmentFiles for the service (e.g. the DNS provider token like
        CF_DNS_API_TOKEN). Substituted into the static config via envsubst.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the web/websecure ports (and :8080 if the insecure dashboard is on).";
    };

    staticConfigOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra static configuration, merged on top of the generated static config.";
    };

    dynamicConfigOptions = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Dynamic configuration (routers, services, middlewares, TLS), merged on top of the generated TLS options and headers middleware.";
    };
  };

  # ANCHOR_END: traefik-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.acme.enable || (cfg.acme.email != "" && cfg.acme.dnsProvider != "");
        message = "othrys.services.traefik: acme.enable requires acme.email and acme.dnsProvider.";
      }
      {
        assertion = !cfg.acme.enable || cfg.environmentFiles != [];
        message = "othrys.services.traefik: DNS-01 ACME needs the provider credential via environmentFiles (e.g. a sops secret exporting the DNS API token).";
      }
    ];

    services.traefik = {
      enable = true;
      inherit (cfg) dataDir group environmentFiles;
      dynamicConfigOptions = lib.recursiveUpdate generatedDynamic cfg.dynamicConfigOptions;
      staticConfigOptions = lib.recursiveUpdate generatedStatic cfg.staticConfigOptions;
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts =
        [80 443]
        ++ lib.optional (cfg.dashboard.enable && cfg.dashboard.insecure) 8080;
    };

    # Certificates (acme.json) must survive reboots under impermanence.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = cfg.dataDir;
          user = "traefik";
          inherit (cfg) group;
          mode = "0700";
        }
      ];
    };
  };
}
