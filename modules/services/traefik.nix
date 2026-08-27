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
          {address = ":443";}
          // lib.optionalAttrs cfg.acme.enable {
            http.tls.certResolver = cfg.acme.resolver;
          };
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
in {
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
      description = "Dynamic configuration (routers, services, middlewares, TLS).";
    };
  };

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
      inherit (cfg) dataDir group environmentFiles dynamicConfigOptions;
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
