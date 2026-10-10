# modules/services/monitoring.nix
# Prometheus metrics export for Grafana integration
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.monitoring;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.services.monitoring = {
    enable = lib.mkEnableOption "Prometheus monitoring";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address Prometheus and the node exporter bind to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus server port.";
    };

    nodePort = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Node exporter port.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall ports for external Grafana access.";
    };

    retentionTime = lib.mkOption {
      type = lib.types.str;
      default = "15d";
      example = "90d";
      description = "Prometheus metric retention (dedicated monitoring hosts usually want more than the 15d default).";
    };

    extraCollectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["ethtool" "smartctl"];
      description = "Node-exporter collectors enabled in addition to the curated base set.";
    };
  };

  config = lib.mkIf cfg.enable {
    # The TSDB. Upstream names the directory below /var/lib through
    # services.prometheus.stateDir and runs the server as the static
    # prometheus account with StateDirectoryMode 0700, so there is no
    # /var/lib/private indirection here. retentionTime describes the window
    # kept on disk, and a wiped root empties it at every boot.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/${config.services.prometheus.stateDir}";
          user = "prometheus";
          group = "prometheus";
          mode = "0700";
        }
      ];
    };

    services.prometheus = {
      enable = true;
      inherit (cfg) port listenAddress retentionTime;
      enableReload = true;

      exporters = {
        node = {
          enable = true;
          port = cfg.nodePort;
          inherit (cfg) listenAddress;
          enabledCollectors =
            [
              "systemd"
              "processes"
              "cpu"
              "meminfo"
              "diskstats"
              "filesystem"
              "loadavg"
              "netdev"
              "netstat"
              "stat"
              "time"
              "uname"
              "vmstat"
            ]
            ++ cfg.extraCollectors;
        };
      };

      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];
              labels = {
                instance = config.networking.hostName;
                job = "node-exporter";
              };
            }
          ];
        }
        {
          job_name = "prometheus";
          static_configs = [
            {
              targets = ["127.0.0.1:${toString config.services.prometheus.port}"];
              labels = {
                instance = config.networking.hostName;
              };
            }
          ];
        }
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      config.services.prometheus.port
      config.services.prometheus.exporters.node.port
    ];
  };
}
