# modules/services/suricata.nix
# Suricata IDS/IPS, wrapping the upstream services.suricata (NixOS 24.11+).
#
# Two inline deliveries:
#   - nfqueue:     packets reach Suricata via an nftables `queue` rule, so the
#                  box stays an L3 router/NAT. The upstream module only knows
#                  AF_PACKET capture, so this module runs Suricata in NFQUEUE
#                  runmode by overriding ExecStart with `-q` and satisfies the
#                  upstream capture-interface assertion with an inert placeholder.
#                  The nftables `queue num` rule that feeds Suricata is the
#                  router/firewall's job (a separate othrys module / the fleet).
#   - af-packet:   Suricata captures on an interface directly. posture=ips builds
#                  a transparent L2 bridge across an interface pair (copy-mode ips);
#                  posture=ids just taps.
#
# Host-specific tuning (isolcpus, CPU core sets, RSS, interface names) is
# identity and stays in the fleet host, so pass deep tuning through `settings`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.services.suricata;

  suricataPkg =
    if cfg.package != null
    then cfg.package
    else pkgs.suricata;

  isIps = cfg.posture == "ips";

  # Common suricata.yaml bits driven by the posture knob.
  postureSettings = {
    exception-policy =
      if isIps
      then "auto" # drop-flow/drop-packet in IPS
      else "ignore"; # never drop in IDS/alert
    host-mode =
      if isIps
      then "router"
      else "auto";
  };

  # AF_PACKET capture config. IDS taps a single interface, while IPS builds a
  # transparent bridge across the interface pair (each side copies to the other).
  afPacketEntries =
    if isIps
    then [
      {
        interface = cfg.afPacket.interface;
        cluster-id = cfg.afPacket.clusterId;
        cluster-type = cfg.afPacket.clusterType;
        copy-mode = "ips";
        copy-iface = cfg.afPacket.copyInterface;
      }
      {
        interface = cfg.afPacket.copyInterface;
        cluster-id = cfg.afPacket.clusterId + 1;
        cluster-type = cfg.afPacket.clusterType;
        copy-mode = "ips";
        copy-iface = cfg.afPacket.interface;
      }
    ]
    else [
      {
        interface = cfg.afPacket.interface;
        cluster-id = cfg.afPacket.clusterId;
        cluster-type = cfg.afPacket.clusterType;
      }
    ];

  modeSettings =
    if cfg.mode == "af-packet"
    then {af-packet = afPacketEntries;}
    else {
      # NFQUEUE runmode reads packets from `-q`, not a capture interface. The
      # `pcap` entry is an inert placeholder so the upstream module's
      # "at least one capture interface" assertion passes, and ExecStart is
      # overridden below to run in NFQUEUE mode, so `lo` is never captured.
      pcap = [{interface = "lo";}];
      nfq = {fail-open = cfg.nfqueue.failOpen;};
    };

  suricataSettings = lib.recursiveUpdate (postureSettings // modeSettings) cfg.settings;
in {
  # ANCHOR: suricata-options
  options.othrys.services.suricata = {
    enable = lib.mkEnableOption "Suricata IDS/IPS";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      defaultText = lib.literalExpression "pkgs.suricata";
      description = "Suricata package to use.";
    };

    mode = lib.mkOption {
      type = lib.types.enum ["nfqueue" "af-packet"];
      default = "nfqueue";
      description = ''
        Inline delivery. `nfqueue` keeps the box an L3 router/NAT (packets are
        queued to Suricata by an nftables `queue` rule). `af-packet` captures on
        an interface (a transparent L2 bridge when posture = ips).
      '';
    };

    posture = lib.mkOption {
      type = lib.types.enum ["ids" "ips"];
      default = "ids";
      description = "IDS alerts only; IPS can drop. Start in IDS, tune, then flip to IPS.";
    };

    enabledSources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["et/open"];
      description = "suricata-update rule sources to enable (sources needing a secret code are unsupported upstream).";
    };

    disabledRules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Rule SIDs/patterns to disable (noisy signatures).";
      example = ["2013504" "2100498"];
    };

    offloadInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ''
        Interfaces on which to disable NIC offloads (GRO/GSO/TSO/LRO) before
        Suricata starts. Required for inline correctness, since offloads create
        super-sized datagrams the inspection path drops.
      '';
      example = ["enp1s0f0" "enp1s0f1"];
    };

    nfqueue = {
      queues = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "Number of NFQUEUE queues (Suricata runs `-q 0 .. -q N-1`); pair with `queue num 0-<N-1>` in nftables and one worker per queue.";
      };

      failOpen = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Let packets pass if Suricata is down/overloaded (fail-open) instead of dropping traffic.";
      };
    };

    afPacket = {
      interface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "enp1s0f0";
        description = "Capture interface for af-packet mode.";
      };

      copyInterface = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "enp1s0f1";
        description = "Peer interface for the af-packet IPS bridge (posture = ips).";
      };

      clusterId = lib.mkOption {
        type = lib.types.ints.positive;
        default = 99;
        description = "af-packet cluster-id (must be unique per Suricata instance on the host).";
      };

      clusterType = lib.mkOption {
        type = lib.types.str;
        default = "cluster_flow";
        description = "af-packet cluster-type (e.g. cluster_flow, cluster_qm).";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra suricata.yaml settings, deep-merged over (and overriding) the generated config, e.g. threading/affinity, outputs, mpm-algo.";
      example = lib.literalExpression ''
        {
          mpm-algo = "hs";
          threading.set-cpu-affinity = true;
        }
      '';
    };
  };
  # ANCHOR_END: suricata-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mode != "af-packet" || cfg.afPacket.interface != null;
        message = "othrys.services.suricata: af-packet mode requires afPacket.interface.";
      }
      {
        assertion = !(cfg.mode == "af-packet" && isIps) || cfg.afPacket.copyInterface != null;
        message = "othrys.services.suricata: af-packet IPS mode requires afPacket.copyInterface (the bridge peer).";
      }
    ];

    services.suricata = {
      enable = true;
      package = suricataPkg;
      inherit (cfg) enabledSources disabledRules;
      settings = suricataSettings;
    };

    # NFQUEUE runmode, where the upstream service captures via `-i`, so override it to
    # read from netfilter queues instead. ExecStartPre (`suricata -T`) is kept.
    systemd.services.suricata.serviceConfig.ExecStart = lib.mkIf (cfg.mode == "nfqueue") (
      lib.mkForce (
        "!${suricataPkg}/bin/suricata -c ${config.services.suricata.configFile}"
        + lib.concatMapStrings (n: " -q ${toString n}") (lib.range 0 (cfg.nfqueue.queues - 1))
      )
    );

    # Inline inspection requires the NIC to hand up physical-sized frames.
    systemd.services.suricata-disable-offload = lib.mkIf (cfg.offloadInterfaces != []) {
      description = "Disable NIC offloads on Suricata-inspected interfaces.";
      before = ["suricata.service"];
      wantedBy = ["suricata.service"];
      after = ["network-pre.target"];
      serviceConfig.Type = "oneshot";
      script = lib.concatMapStringsSep "\n" (iface: "${pkgs.ethtool}/bin/ethtool -K ${iface} gro off gso off tso off lro off || true") cfg.offloadInterfaces;
    };
  };
}
