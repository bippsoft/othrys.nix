# modules/services/scrutiny.nix
# Scrutiny, S.M.A.R.T. disk health with history
#
# smartd alarms when an attribute crosses a threshold, while Scrutiny keeps
# every reading in InfluxDB and judges devices against Backblaze's observed
# failure rates, which is how a slowly dying disk becomes visible months
# before smartd has anything to say.
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
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.scrutiny;
  notifyCfg = config.othrys.services.notify;

  # Anything between the scheme and an `@` ahead of the first slash, which
  # is a user, a user and password, or a token.
  carriesUserinfo = url: url != null && builtins.match ".*://[^/?#]*@.*" url != null;

  # "http(s)://host:port" → the shoutrrr ntfy form Scrutiny understands.
  # shoutrrr assumes https, and the ?scheme query carries a plain-http origin.
  ntfyShoutrrr = url: topic:
    if lib.hasPrefix "https://" url
    then "ntfy://${lib.removePrefix "https://" url}/${topic}"
    else "ntfy://${lib.removePrefix "http://" url}/${topic}?scheme=http";
in {
  # ANCHOR: scrutiny-options
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
        lib.optional (notifyCfg.enable && notifyCfg.url != null && notifyCfg.tokenFile == null && !config.othrys.internal.notifyRefusedLocally)
        (ntfyShoutrrr notifyCfg.url notifyCfg.topic);
      defaultText = lib.literalExpression "the othrys.services.notify endpoint as a shoutrrr ntfy URL, when notify is enabled, unauthenticated and not refused by the ntfy server on this host; else []";
      example = ["ntfy://ntfy.example.com/alerts"];
      description = "shoutrrr URLs Scrutiny pushes device-failure notifications to. Follows the fleet notify channel by default. A token-authenticated notify endpoint is NOT auto-wired (the token would end up world-readable in the rendered config). Pass an explicit URL instead. Nothing is wired either when notify points at the ntfy server on this host with no token while that server denies anonymous clients, since every push would be refused.";
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
        description = ''
          Scrutiny API base URL the collector reports to. Null means the local
          web UI, which suits a hub, and a satellite must set it. The value
          is written to the collector's unit and configuration in the store,
          so a URL with a user, password or token before the host is refused.
          A hub behind a proxy that asks for credentials is reached through
          `environmentFile`.
        '';
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."scrutiny/collector-env".path'';
        description = ''
          Environment file read by the collector unit, a secrets-provider
          path. A line `COLLECTOR_API_ENDPOINT=https://user:password@scrutiny.example.com`
          in it replaces `endpoint` at run time, which is how the collector
          authenticates to a hub behind a proxy without the credentials
          entering the store. Upstream types the endpoint as a plain string
          and has no file form for it.
        '';
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

  # ANCHOR_END: scrutiny-options

  config = lib.mkIf (cfg.enable || cfg.collector.enable) {
    # The hub's web UI and its collector API carry no authentication of
    # their own: anyone who reaches the port reads every disk and can post
    # readings. Loopback behind a proxy that authenticates is the shape.
    warnings = lib.optional (cfg.enable && (cfg.openFirewall || (cfg.listenAddress != "127.0.0.1" && cfg.listenAddress != "::1"))) "othrys.services.scrutiny: the hub listens on ${cfg.listenAddress}${lib.optionalString cfg.openFirewall " with the port open"} and has no authentication of its own; put an authenticating proxy in front or keep it on loopback.";

    assertions = [
      {
        assertion = cfg.collector.enable -> (cfg.enable || cfg.collector.endpoint != null);
        message = "othrys.services.scrutiny: a collector-only host must set collector.endpoint (there is no local web UI to report to).";
      }
      {
        assertion = !carriesUserinfo cfg.collector.endpoint;
        message = "othrys.services.scrutiny: collector.endpoint carries credentials in its URL, which would be written to the store. Leave them out of endpoint and put COLLECTOR_API_ENDPOINT with the full URL in collector.environmentFile.";
      }
      # The hub binds `port`; a collector-only host binds nothing, so the
      # clash is the hub's alone.
      {
        assertion = !(cfg.enable && config.othrys.services.security.crowdsec.enable && cfg.port == 8080);
        message = "othrys.services.scrutiny: port 8080 is where the CrowdSec local API listens on this host. Give Scrutiny another port.";
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
    systemd.services.scrutiny-collector = lib.mkIf cfg.collector.enable {
      onFailure = lib.mkIf notifyCfg.enable ["notify-failure@%n.service"];
      # systemd applies an EnvironmentFile after the unit's own Environment
      # lines, so a COLLECTOR_API_ENDPOINT in the file replaces the one
      # upstream renders from `endpoint`.
      serviceConfig.EnvironmentFile = lib.mkIf (cfg.collector.environmentFile != null) [cfg.collector.environmentFile];
    };

    # Scrutiny's device DB + the InfluxDB time series. The upstream unit runs
    # with DynamicUser + StateDirectory, so the real directory is under
    # /var/lib/private and /var/lib/scrutiny is systemd's symlink to it.
    othrys.internal.persist."services.scrutiny" = {
      directories =
        lib.optionals cfg.enable
        [
          {
            directory = "/var/lib/private/scrutiny";
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
