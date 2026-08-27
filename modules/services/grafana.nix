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
  cfg = config.othrys.services.grafana;
  monitoringCfg = config.othrys.services.monitoring;
  vmCfg = config.othrys.services.victoriametrics;
  vlCfg = config.othrys.services.victorialogs;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # A store listening on all interfaces is still queried locally, since Grafana
  # runs on the same host as every auto-provisioned datasource.
  local = addr:
    if addr == "0.0.0.0"
    then "127.0.0.1"
    else addr;
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

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."grafana/admin-password".path'';
      description = "Path to a runtime file holding the admin password (a secrets-provider path). Null keeps Grafana's initial-setup default.";
    };

    secretKeyFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      defaultText = lib.literalMD "none, and an assertion rejects an unset value once the module is enabled";
      example = lib.literalExpression ''config.sops.secrets."grafana/secret-key".path'';
      description = "Path to a runtime file holding Grafana's secret_key (encrypts stored credentials, so generate a random string). Must be set when this module is enabled, since upstream no longer ships a default. Use a secrets-provider path.";
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
    ];

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
        server = {
          http_addr = cfg.listenAddress;
          http_port = cfg.port;
        };
        # Guarded interpolations, since a null path in "$__file{...}" is an
        # uncatchable type error that would preempt the assertion above.
        security =
          lib.optionalAttrs (cfg.secretKeyFile != null) {
            secret_key = "$__file{${cfg.secretKeyFile}}";
          }
          // lib.optionalAttrs (cfg.adminPasswordFile != null) {
            admin_password = "$__file{${cfg.adminPasswordFile}}";
          };
        analytics.reporting_enabled = false;
      };

      provision = {
        enable = true;

        datasources.settings.datasources =
          lib.optional monitoringCfg.enable {
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString monitoringCfg.port}";
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
