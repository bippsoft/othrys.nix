# modules/services/victoriametrics.nix
# VictoriaMetrics, a fast and resource-efficient time-series database with a
# Prometheus-compatible API (scrape, remote-write, MetricsQL). A thin wrapper
# over services.victoriametrics, loopback by default (reverse proxy in front),
# retention as policy, and optional scraping of the node exporter the
# othrys monitoring module runs.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.victoriametrics;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  monitoringCfg = config.othrys.services.monitoring;

  scrapeConfigs =
    lib.optional cfg.scrapeNodeExporter {
      job_name = "node";
      static_configs = [
        {
          targets = ["127.0.0.1:${toString monitoringCfg.nodePort}"];
          labels = {
            instance = config.networking.hostName;
            job = "node-exporter";
          };
        }
      ];
    }
    ++ cfg.scrapeConfigs;
in {
  # ANCHOR: victoriametrics-options
  options.othrys.services.victoriametrics = {
    enable = lib.mkEnableOption "VictoriaMetrics single-node time-series database (Prometheus-compatible)";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address VictoriaMetrics listens on. Loopback by default, expecting a reverse proxy in front; set to 0.0.0.0 to expose it directly.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8428;
      description = "Port VictoriaMetrics listens on (HTTP API: scrape, remote-write, query).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall. Leave off when a reverse proxy fronts VictoriaMetrics (the default).";
    };

    retentionPeriod = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "1y";
      description = "How long to retain samples (suffixes s/h/d/w/y, a bare number is months). Null uses the upstream default (1 month), and long-term storage hosts usually want more.";
    };

    scrapeNodeExporter = lib.mkOption {
      type = lib.types.bool;
      default = monitoringCfg.enable;
      defaultText = lib.literalExpression "config.othrys.services.monitoring.enable";
      description = "Scrape the local node exporter (at othrys.services.monitoring.nodePort). Follows the monitoring module by default so enabling both wires them together.";
    };

    scrapeConfigs = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [];
      example = lib.literalExpression ''
        [
          {
            job_name = "headscale";
            static_configs = [{targets = ["127.0.0.1:9090"];}];
          }
        ]
      '';
      description = "Additional Prometheus-style scrape configs appended to the generated set.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["-dedup.minScrapeInterval=15s"];
      description = "Extra command-line flags passed to VictoriaMetrics.";
    };
  };
  # ANCHOR_END: victoriametrics-options

  config = lib.mkIf cfg.enable {
    # TSDB storage. The upstream unit runs with DynamicUser + StateDirectory,
    # so the real data lives under /var/lib/private (see ollama for the same
    # pattern).
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/private/victoriametrics";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    services.victoriametrics = {
      enable = true;
      listenAddress = "${cfg.listenAddress}:${toString cfg.port}";
      inherit (cfg) retentionPeriod;
      extraOptions = cfg.extraFlags;
      # Only materialize a scrape config when there is something to scrape.
      prometheusConfig = lib.mkIf (scrapeConfigs != []) {
        scrape_configs = scrapeConfigs;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
