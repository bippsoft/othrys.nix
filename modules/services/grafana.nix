# modules/services/grafana.nix
# Grafana dashboards. Datasources are auto-provisioned from whichever othrys
# stores are enabled on the same host (Prometheus via monitoring,
# VictoriaMetrics, VictoriaLogs, the last with its datasource plugin
# installed). Enabling grafana next to any of them wires them together with
# zero config.
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  inherit (import ../lib/net.nix {inherit lib;}) local;
  cfg = config.othrys.services.grafana;
  monitoringCfg = config.othrys.services.monitoring;
  vmCfg = config.othrys.services.victoriametrics;
  vlCfg = config.othrys.services.victorialogs;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  loopback = cfg.listenAddress == "127.0.0.1" || cfg.listenAddress == "::1" || cfg.listenAddress == "localhost";
  # Opening the port on a loopback listener publishes nothing, but a consumer
  # who sets it means to expose Grafana, so the stricter rules apply.
  exposed = !loopback || cfg.openFirewall;
in {
  # ANCHOR: grafana-options
  options.othrys.services.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards (datasources auto-provisioned from enabled othrys metrics stores)";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address Grafana listens on. Loopback by default, expecting a reverse proxy in front.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Port Grafana listens on (3001, since the docs server claims 3000 by default).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall. Leave off when a reverse proxy fronts Grafana (the default).";
    };

    rootUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://grafana.example.com/";
      description = "Public URL Grafana is reached at, written to `server.root_url`. Redirects, OIDC callbacks and the secure flag on the session cookie follow it, so it must be set when `listenAddress` is not loopback. Null keeps Grafana's default, which names localhost.";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."grafana/admin-password".path'';
      description = ''
        Path to a runtime file holding the admin password (a secrets-provider
        path). Grafana reads it as the `grafana` user, so with sops-nix set
        `owner = "grafana"` on the secret. The value is applied when the
        database is first created and ignored afterwards, and the password of
        an existing instance changes with
        `grafana cli admin reset-admin-password`. Null keeps the stock
        admin/admin credential, which the module warns about on loopback and
        refuses when `listenAddress` is not loopback or `openFirewall` is on.
      '';
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      defaultText = lib.literalMD "none, and an assertion rejects an unset value once the module is enabled";
      example = lib.literalExpression ''config.sops.secrets."grafana/secret-key".path'';
      description = ''
        Path to a runtime file holding Grafana's secret_key (encrypts stored
        credentials, so generate a random string). Must be set when this
        module is enabled, since upstream no longer ships a default. Use a
        secrets-provider path, readable by the `grafana` user, which with
        sops-nix is `owner = "grafana"` on the secret.
      '';
    };

    extraDatasources = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [];
      description = "Datasources provisioned in addition to the auto-detected othrys metrics stores.";
    };

    dashboardsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Directory of dashboard JSON files to provision (fleet-provided).";
    };
  };
  # ANCHOR_END: grafana-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretKeyFile != null;
        message = "othrys.services.grafana: set secretKeyFile (a secrets-provider path to a random string; Grafana encrypts stored credentials with it and upstream ships no default).";
      }
      # Without a password file Grafana serves admin/admin. On loopback a
      # reverse proxy decides who reaches it and the warning below suffices.
      # Off loopback, or with the port open, anyone who reaches the port
      # has the stock credential.
      {
        assertion = exposed -> cfg.adminPasswordFile != null;
        message = "othrys.services.grafana: set adminPasswordFile (a secrets-provider path to the admin password; without it Grafana serves the stock admin/admin credential on ${cfg.listenAddress}${lib.optionalString cfg.openFirewall " with the port open"}).";
      }
      # Grafana builds redirects and OIDC callback URLs from root_url, and
      # its default names localhost, which only works for a loopback listener.
      {
        assertion = loopback || cfg.rootUrl != null;
        message = "othrys.services.grafana: set rootUrl (the public URL, as https://grafana.example.com/) when listenAddress is not loopback, since redirects and OIDC callbacks are built from it and the default names localhost.";
      }
    ];

    warnings = lib.optional (!exposed && cfg.adminPasswordFile == null) "othrys.services.grafana: no adminPasswordFile is set, so Grafana serves the stock admin/admin credential on ${cfg.listenAddress}:${toString cfg.port}. Set one before putting a proxy in front.";

    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/grafana";
          user = "grafana";
          group = "grafana";
          mode = "0700";
        }
      ];
    };

    services.grafana = {
      enable = true;

      # The VictoriaLogs datasource type ships as a plugin (signed, packaged
      # in nixpkgs), and Prometheus-compatible types need nothing.
      declarativePlugins =
        lib.mkIf vlCfg.enable [pkgs.grafanaPlugins.victoriametrics-logs-datasource];

      settings = {
        server =
          {
            http_addr = cfg.listenAddress;
            http_port = cfg.port;
          }
          // lib.optionalAttrs (cfg.rootUrl != null) {
            root_url = cfg.rootUrl;
          };
        # Guarded interpolations, since a null path in "$__file{...}" is an
        # uncatchable type error that would preempt the assertion above.
        security =
          lib.optionalAttrs (cfg.secretKeyFile != null) {
            secret_key = "$__file{${cfg.secretKeyFile}}";
          }
          // lib.optionalAttrs (cfg.adminPasswordFile != null) {
            admin_password = "$__file{${cfg.adminPasswordFile}}";
          }
          // {
            # The secure flag follows the scheme of the public URL. A browser
            # drops a secure cookie that arrives over plain http, so marking
            # it secure on a loopback or http-only deployment would make
            # every login fail, and leaving it off behind a TLS proxy would
            # let a browser send the session cookie over plain http.
            cookie_secure = lib.mkDefault (cfg.rootUrl != null && lib.hasPrefix "https://" cfg.rootUrl);
          };
        # Accounts come from the admin or an identity provider, never from
        # the login page.
        users.allow_sign_up = lib.mkDefault false;
        analytics.reporting_enabled = false;
      };

      provision = {
        enable = true;

        # Every store runs on this host, so each URL is its listener seen from
        # here (modules/lib/net.nix), which keeps a store moved to one
        # interface reachable and a store on every interface on loopback.
        datasources.settings.datasources =
          lib.optional monitoringCfg.enable {
            name = "Prometheus";
            type = "prometheus";
            url = "http://${local monitoringCfg.listenAddress}:${toString monitoringCfg.port}";
            isDefault = !vmCfg.enable;
          }
          ++ lib.optional vmCfg.enable {
            name = "VictoriaMetrics";
            type = "prometheus";
            url = "http://${local vmCfg.listenAddress}:${toString vmCfg.port}";
            isDefault = true;
          }
          # Unlike the two above, this type is a plugin, not built in, so the
          # declarativePlugins entry below is what makes it queryable rather
          # than a datasource that lists but errors.
          ++ lib.optional vlCfg.enable {
            name = "VictoriaLogs";
            type = "victoriametrics-logs-datasource";
            url = "http://${local vlCfg.listenAddress}:${toString vlCfg.port}";
            isDefault = false;
          }
          ++ cfg.extraDatasources;

        dashboards.settings.providers = lib.optional (cfg.dashboardsDir != null) {
          name = "othrys";
          options.path = cfg.dashboardsDir;
        };
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
