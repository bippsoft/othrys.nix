# modules/services/scrutiny.nix
# Scrutiny, S.M.A.R.T. disk health with history. smartd alarms when an
# attribute crosses a threshold, while Scrutiny keeps every reading in InfluxDB and
# judges devices against Backblaze's observed failure rates, which is how a
# slowly dying disk becomes visible months before smartd has anything to say.
#
# A thin wrapper over services.scrutiny with a hub-and-spoke shape:
#
#   * hub, `enable = true`: web UI + InfluxDB (managed by the upstream
#     module), loopback by default (reverse proxy in front), plus a local
#     collector for the hub's own disks.
#   * satellite, only `collector.enable = true` + `collector.endpoint`
#     pointing at the hub: no web UI, no InfluxDB, just smartctl readings
#     POSTed on a timer.
#
# Failure notifications follow othrys.services.notify by default. When notify
# is enabled, its ntfy endpoint is re-expressed as the shoutrrr URL Scrutiny
# speaks natively, giving one fleet alert channel and no second config.
#
# The upstream collector unit also enables smartd, which composes with
# othrys.hardware.smart (list-merged options), so hosts running both keep
# their immediate smartd warnings alongside the trend history.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.scrutiny;
  notifyCfg = config.othrys.services.notify;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # "http(s)://host:port" → the shoutrrr ntfy form Scrutiny understands.
  # shoutrrr assumes https, and the ?scheme query carries a plain-http origin.
  ntfyShoutrrr = url: topic:
    if lib.hasPrefix "https://" url
    then "ntfy://${lib.removePrefix "https://" url}/${topic}"
    else "ntfy://${lib.removePrefix "http://" url}/${topic}?scheme=http";
in {
  options.othrys.services.scrutiny = {
    enable = lib.mkEnableOption "the Scrutiny hub: web UI + InfluxDB, and a collector for this host's own disks";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address the web UI listens on. Loopback by default, expecting a reverse proxy in front; satellites then report in through the proxied URL.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port the web UI (and collector API) listens on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall. Leave off when a reverse proxy fronts the web UI (the default).";
    };

    notifyUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default =
        lib.optional (notifyCfg.enable && notifyCfg.url != null && notifyCfg.tokenFile == null)
        (ntfyShoutrrr notifyCfg.url notifyCfg.topic);
      defaultText = lib.literalExpression "the othrys.services.notify endpoint as a shoutrrr ntfy URL, when notify is enabled and unauthenticated; else []";
      example = ["ntfy://ntfy.example.com/alerts"];
      description = "shoutrrr URLs Scrutiny pushes device-failure notifications to. Follows the fleet notify channel by default. A token-authenticated notify endpoint is NOT auto-wired (the token would end up world-readable in the rendered config). Pass an explicit URL instead.";
    };

    collector = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        defaultText = lib.literalExpression "config.othrys.services.scrutiny.enable";
        description = "Run the smartctl collector on this host. Follows `enable` (a hub watches its own disks); set alone on satellite hosts, with `endpoint`.";
      };

      endpoint = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://scrutiny.example.com";
        description = "Scrutiny API base URL the collector reports to. Null means the local web UI (hub hosts); satellites must set it.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd calendar expression for collector runs. Daily is enough, since smartd covers the fast alarms and this feeds the trend history.";
      };

      hostId = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        defaultText = lib.literalExpression "config.networking.hostName";
        description = "Label the web UI groups this host's disks under.";
      };
    };
  };

  config = lib.mkIf (cfg.enable || cfg.collector.enable) {
    assertions = [
      {
        assertion = cfg.collector.enable -> (cfg.enable || cfg.collector.endpoint != null);
        message = "othrys.services.scrutiny: a collector-only host must set collector.endpoint (there is no local web UI to report to).";
      }
    ];

    services.scrutiny = {
      inherit (cfg) enable openFirewall;

      settings = lib.mkIf cfg.enable {
        web.listen = {
          host = cfg.listenAddress;
          inherit (cfg) port;
        };

        # The upstream default is the connect-to-0.0.0.0 quirk, so be explicit,
        # matching the loopback bind below. mkDefault so a host pointing at an
        # external InfluxDB can override alongside influxdb.enable = false.
        web.influxdb.host = lib.mkDefault "127.0.0.1";

        notify = lib.mkIf (cfg.notifyUrls != []) {urls = cfg.notifyUrls;};
      };

      collector = {
        inherit (cfg.collector) enable schedule;
        settings = {
          host.id = cfg.collector.hostId;
          # When null, the upstream default derives the local web UI's address
          # from web.listen above, exactly right for a hub.
          api.endpoint = lib.mkIf (cfg.collector.endpoint != null) cfg.collector.endpoint;
        };
      };
    };

    # The upstream module manages InfluxDB "with default options", which bind
    # every interface. Nothing but the local Scrutiny reads it.
    services.influxdb2.settings = lib.mkIf (cfg.enable && config.services.scrutiny.influxdb.enable) {
      http-bind-address = lib.mkDefault "127.0.0.1:8086";
    };

    # A collector that stops running is a monitoring gap that looks like good
    # news, so route the oneshot's failures into the fleet channel.
    systemd.services.scrutiny-collector.onFailure =
      lib.mkIf (cfg.collector.enable && notifyCfg.enable) ["notify-failure@%n.service"];

    # Scrutiny's device DB + the InfluxDB time series.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories =
        lib.optionals cfg.enable
        [
          {
            directory = "/var/lib/scrutiny";
            user = "root";
            group = "root";
            mode = "0750";
          }
          {
            directory = "/var/lib/influxdb2";
            user = "influxdb2";
            group = "influxdb2";
            mode = "0700";
          }
        ];
    };
  };
}
