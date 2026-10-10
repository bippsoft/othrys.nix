# flake/checks/listen-eval.nix
# CORE. Where the metrics, logs, dashboard and alerting modules tell their
# local consumers to find each other, read back from evaluated hosts. The
# scrape targets, datasource URLs and journal upload once wrote loopback while
# the listener bound whatever listenAddress named, so moving a store to one
# interface left its consumers connecting to a port nothing listened on, and
# the alerting datasource wrote 0.0.0.0 verbatim. The Prometheus job name was
# also replaced by a label of another name. None of that fails evaluation.
{
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  # Every listener on one address. ntfy is included so notify's default URL is
  # read back too.
  stack = address:
    hostConfig [
      functioningHost
      {
        othrys.services.monitoring = {
          enable = true;
          listenAddress = address;
        };
        othrys.services.victoriametrics = {
          enable = true;
          listenAddress = address;
        };
        othrys.services.victorialogs = {
          enable = true;
          listenAddress = address;
        };
        othrys.services.grafana = {
          enable = true;
          listenAddress = address;
          secretKeyFile = "/run/secrets/grafana/secret-key";
          adminPasswordFile = "/run/secrets/grafana/admin-password";
        };
        othrys.services.alerting = {
          enable = true;
          listenAddress = address;
        };
        othrys.services.ntfy = {
          enable = true;
          listenAddress = address;
        };
        othrys.services.notify.enable = true;
      }
    ];

  specific = stack "192.0.2.10";
  wildcard = stack "0.0.0.0";

  # Alerting falls back to Prometheus when VictoriaMetrics is off.
  prometheusOnly = hostConfig [
    functioningHost
    {
      othrys.services.monitoring = {
        enable = true;
        listenAddress = "192.0.2.10";
      };
      othrys.services.alerting.enable = true;
      othrys.services.notify.url = "https://ntfy.example.com";
      othrys.services.notify.enable = true;
    }
  ];

  notify = url:
    hostConfig [
      functioningHost
      {
        othrys.services.notify = {
          enable = true;
          inherit url;
          tokenFile = "/run/secrets/notify-token";
        };
      }
    ];
  notifyHttp = notify "http://ntfy.example.com";
  notifyHttps = notify "https://ntfy.example.com";
  notifyLoopback = notify "http://127.0.0.1:2586";

  warnsAbout = needle: cfg: builtins.any (w: builtins.match ".*${needle}.*" w != null) cfg.warnings;

  # Prometheus scrape configs by job name, each reduced to its first target
  # and its target labels.
  prometheusJobs = cfg:
    builtins.listToAttrs (map (job: {
        name = job.job_name;
        value = {
          target = builtins.head (builtins.head job.static_configs).targets;
          labels = (builtins.head job.static_configs).labels or {};
        };
      })
      cfg.services.prometheus.scrapeConfigs);
  vmJobs = cfg:
    builtins.listToAttrs (map (job: {
        name = job.job_name;
        value = {
          target = builtins.head (builtins.head job.static_configs).targets;
          labels = (builtins.head job.static_configs).labels or {};
        };
      })
      cfg.services.victoriametrics.prometheusConfig.scrape_configs);
  datasources = cfg:
    builtins.listToAttrs (map (ds: {
        inherit (ds) name;
        value = ds.url;
      })
      cfg.services.grafana.provision.datasources.settings.datasources);
  journalUrl = cfg: cfg.services.journald.upload.settings.Upload.URL;
  alertingSource = cfg: cfg.services.vmalert.instances.othrys.settings."datasource.url";
  notifyUrl = cfg: cfg.othrys.services.notify.url;

  # Every consumer on `cfg` reaches its listener at `at`.
  reaches = at: cfg:
    (prometheusJobs cfg).node-exporter.target
    == "${at}:9100"
    && (prometheusJobs cfg).prometheus.target == "${at}:9090"
    && (vmJobs cfg).node-exporter.target == "${at}:9100"
    && (datasources cfg).Prometheus == "http://${at}:9090"
    && (datasources cfg).VictoriaMetrics == "http://${at}:8428"
    && (datasources cfg).VictoriaLogs == "http://${at}:9428"
    && journalUrl cfg == "http://${at}:9428/insert/journald"
    && alertingSource cfg == "http://${at}:8428"
    && notifyUrl cfg == "http://${at}:2586";
in
  mkExpectations "othrys-eval-listen" {
    "a stack on one address is scraped, queried and fed at that address" = reaches "192.0.2.10" specific;
    "a stack on every interface is scraped, queried and fed on loopback" = reaches "127.0.0.1" wildcard;
    "alerting falls back to Prometheus at its own address" = alertingSource prometheusOnly == "http://192.0.2.10:9090";
    "the Prometheus node job is named for the label the rules see" = (prometheusJobs specific) ? node-exporter && !((prometheusJobs specific).node-exporter.labels ? job);
    "the VictoriaMetrics node job is named for the label the rules see" = (vmJobs specific) ? node-exporter && !((vmJobs specific).node-exporter.labels ? job);
    "a token over plain http to another host warns" = warnsAbout "sent in clear" notifyHttp;
    "a token over https does not warn" = !warnsAbout "sent in clear" notifyHttps;
    "a token over plain http to loopback does not warn" = !warnsAbout "sent in clear" notifyLoopback;
    "no token does not warn" = !warnsAbout "sent in clear" specific;
  }
