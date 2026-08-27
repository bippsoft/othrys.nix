# modules/services/alerting.nix
# Alert evaluation via vmalert, datasource-agnostic (any Prometheus-
# compatible HTTP API: VictoriaMetrics, Prometheus). The datasource is
# discovered from whichever othrys metrics store is enabled, and delivery flows
# to othrys.services.notify through an internal
# alertmanager -> alertmanager-ntfy chain (vmalert only speaks the
# Alertmanager API, and both hops are loopback implementation details, while the
# consumer surface is rules in, ntfy notifications out).
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.alerting;
  monitoringCfg = config.othrys.services.monitoring;
  vmCfg = config.othrys.services.victoriametrics;
  notifyCfg = config.othrys.services.notify;

  internalDelivery = notifyCfg.enable && cfg.notifierUrls == [];
  alertmanagerPort = 9093;
  bridgePort = 8489;

  starterGroups = [
    {
      name = "othrys";
      rules = [
        {
          alert = "InstanceDown";
          expr = "up == 0";
          for = "5m";
          labels.severity = "critical";
          annotations.summary = "{{ $labels.instance }} target {{ $labels.job }} is down";
        }
        {
          alert = "DiskSpaceLow";
          expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay"} / node_filesystem_size_bytes) < 0.10'';
          for = "15m";
          labels.severity = "warning";
          annotations.summary = "{{ $labels.instance }} {{ $labels.mountpoint }} below 10% free";
        }
        {
          alert = "MemoryPressure";
          expr = "(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.05";
          for = "10m";
          labels.severity = "warning";
          annotations.summary = "{{ $labels.instance }} below 5% available memory";
        }
      ];
    }
  ];
in {
  # ANCHOR: alerting-options
  options.othrys.services.alerting = {
    enable = lib.mkEnableOption "alert rule evaluation (vmalert) with ntfy delivery";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address vmalert's HTTP interface listens on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8880;
      description = "Port vmalert's HTTP interface listens on.";
    };

    datasourceUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if vmCfg.enable
        then "http://${vmCfg.listenAddress}:${toString vmCfg.port}"
        else if monitoringCfg.enable
        then "http://127.0.0.1:${toString monitoringCfg.port}"
        else null;
      defaultText = lib.literalExpression "the local VictoriaMetrics instance when enabled, else the local Prometheus, else null";
      description = "Prometheus-compatible datasource rules are evaluated against. Auto-discovered from the enabled othrys metrics store.";
    };

    notifierUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["http://127.0.0.1:9093"];
      description = "Alertmanager endpoints alerts are sent to. Empty with othrys.services.notify enabled runs the internal alertmanager -> ntfy delivery chain.";
    };

    starterRules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include the curated starter rules (instance down, disk space, memory pressure).";
    };

    ruleGroups = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [];
      description = "Additional Prometheus-style rule groups appended to the starter set.";
    };
  };
  # ANCHOR_END: alerting-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.datasourceUrl != null;
        message = "othrys.services.alerting: no datasource. Enable othrys.services.victoriametrics or othrys.services.monitoring, or set datasourceUrl.";
      }
      {
        assertion = cfg.notifierUrls != [] || notifyCfg.enable;
        message = "othrys.services.alerting: no delivery path. Enable othrys.services.notify (internal chain) or set notifierUrls.";
      }
    ];

    services.vmalert.instances.othrys = {
      enable = true;
      settings = {
        "datasource.url" = cfg.datasourceUrl;
        "notifier.url" =
          if internalDelivery
          then ["http://127.0.0.1:${toString alertmanagerPort}"]
          else cfg.notifierUrls;
        httpListenAddr = "${cfg.listenAddress}:${toString cfg.port}";
      };
      rules = {
        groups = lib.optionals cfg.starterRules starterGroups ++ cfg.ruleGroups;
      };
    };

    # The internal delivery chain runs alertmanager (grouping/dedup) into the
    # alertmanager-ntfy bridge -> the notify endpoint. Both loopback-only.
    services.prometheus.alertmanager = lib.mkIf internalDelivery {
      enable = true;
      listenAddress = "127.0.0.1";
      port = alertmanagerPort;
      configuration = {
        route = {
          receiver = "ntfy";
          group_by = ["alertname" "instance"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
        };
        receivers = [
          {
            name = "ntfy";
            webhook_configs = [{url = "http://127.0.0.1:${toString bridgePort}/hook";}];
          }
        ];
      };
    };

    services.prometheus.alertmanager-ntfy = lib.mkIf internalDelivery {
      enable = true;
      settings = {
        http.addr = "127.0.0.1:${toString bridgePort}";
        ntfy = {
          baseurl = notifyCfg.url;
          notification.topic = notifyCfg.topic;
        };
      };
    };
  };
}
