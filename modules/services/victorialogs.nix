# modules/services/victorialogs.nix
# VictoriaLogs, a log database from the VictoriaMetrics family (LogsQL,
# resource-efficient). Pairs with othrys.services.victoriametrics for the
# full metrics+logs store. The host's journal ships to it natively via
# systemd-journal-upload (no extra agent).
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.victorialogs;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  # ANCHOR: victorialogs-options
  options.othrys.services.victorialogs = {
    enable = lib.mkEnableOption "VictoriaLogs log database (LogsQL, journald ingestion)";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address VictoriaLogs listens on. Loopback by default, expecting a reverse proxy in front.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 9428;
      description = "Port VictoriaLogs listens on (HTTP API: ingestion and LogsQL queries).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall. Leave off when a reverse proxy fronts VictoriaLogs (the default).";
    };

    retentionPeriod = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "12w";
      description = "How long to retain logs (suffixes: h/d/w/y; a bare number is months). Null uses the upstream default (7 days).";
    };

    collectJournal = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ship this host's systemd journal into VictoriaLogs via systemd-journal-upload.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra command-line flags passed to VictoriaLogs.";
    };
  };
  # ANCHOR_END: victorialogs-options

  config = lib.mkIf cfg.enable {
    # Log storage. The upstream unit runs with DynamicUser + StateDirectory,
    # so the real data lives under /var/lib/private (the victoriametrics
    # pattern).
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/private/victorialogs";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    services.victorialogs = {
      enable = true;
      listenAddress = "${cfg.listenAddress}:${toString cfg.port}";
      extraOptions =
        lib.optional (cfg.retentionPeriod != null) "-retentionPeriod=${cfg.retentionPeriod}"
        ++ cfg.extraFlags;
    };

    # Native journald ingestion, where systemd-journal-upload speaks to
    # VictoriaLogs' /insert/journald endpoint directly.
    services.journald.upload = lib.mkIf cfg.collectJournal {
      enable = true;
      settings.Upload.URL = "http://127.0.0.1:${toString cfg.port}/insert/journald";
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
