# flake/checks/router-services.nix
# CORE. Two start-up defaults of the router's security services, read back from
# the evaluated host. Both failures they guard against only show on a host with
# a route out, which no VM test has, so they are pinned here.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
}: let
  host = extra:
    hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
        networking.nftables.enable = true;
      }
      extra
    ];

  suricataHost = extra:
    host {
      imports = [
        {
          othrys.services.suricata = {
            enable = true;
            mode = "nfqueue";
          };
        }
        extra
      ];
    };
  suricata = settings: (suricataHost {othrys.services.suricata = {inherit settings;};}).services.suricata.settings.app-layer.protocols;
  ips = suricataHost {
    othrys.services.suricata = {
      posture = "ips";
      offloadInterfaces = ["wan0" "eth0.100"];
      dropRules = ["re:trojan"];
    };
  };
  pairedRouter = queues:
    suricataHost {
      othrys.services.suricata.nfqueue.queues = 2;
      othrys.services.router = {
        enable = true;
        wan.interface = "wan0";
        lan.interfaces = ["lan0"];
        suricata = {
          enable = true;
          inherit queues;
        };
      };
    };
  afPacketRouter = suricataHost ({lib, ...}: {
    othrys.services.suricata = {
      mode = lib.mkForce "af-packet";
      afPacket.interface = "lan0";
    };
    othrys.services.router = {
      enable = true;
      wan.interface = "wan0";
      lan.interfaces = ["lan0"];
      suricata.enable = true;
    };
  });
  offload = ips.systemd.services.suricata-disable-offload;

  crowdsecAfter = unbound:
    (host {
      othrys.services.security.crowdsec = {
        enable = true;
        collections = [];
      };
      othrys.services.unbound.enable = unbound;
    }).systemd.services.crowdsec.after;

  crowdsecOn = extra:
    host {
      imports = [
        {
          othrys.services.security.crowdsec = {
            enable = true;
            collections = [];
          };
        }
        extra
      ];
    };
  onRouter = crowdsecOn {
    othrys.services.router = {
      enable = true;
      wan.interface = "wan0";
      lan.interfaces = ["lan0"];
    };
  };
  alone = crowdsecOn {};
  withTraefik = crowdsecOn {othrys.services.traefik.enable = true;};
  hasInfix = needle: s: builtins.match ".*${needle}.*" s != null;
  bouncerTable = cfg: family: cfg.networking.nftables.tables.${family}.content;
in
  mkExpectations "othrys-eval-router-services" {
    "suricata states modbus as off so suricata-update drops its rules" = (suricata {}).modbus.enabled == "no";
    "suricata states dnp3 as off so suricata-update drops its rules" = (suricata {}).dnp3.enabled == "no";
    "a host that turns a parser on keeps its value" = (suricata {app-layer.protocols.modbus.enabled = "yes";}).modbus.enabled == "yes";
    "the other protocol keeps its default beside an override" = (suricata {app-layer.protocols.modbus.enabled = "yes";}).dnp3.enabled == "no";
    "a running engine reloads its rules after an update" = ips.services.suricata.reloadOnRulesetUpdate;
    "dropRules reach suricata-update" = ips.services.suricata.dropRules == ["re:trojan"];
    "the offload unit is bound to its interfaces' device units" = builtins.elem "sys-subsystem-net-devices-wan0.device" offload.bindsTo && builtins.elem "sys-subsystem-net-devices-eth0.100.device" offload.after;
    "the offload unit no longer swallows an ethtool failure" = builtins.match ".*\\|\\| true.*" offload.script == null;
    "matching queue counts are accepted" = !rejectedWith "queues" (pairedRouter 2);
    "a queue count that differs from the router's is rejected" = rejectedWith "differ; packets sent to a queue" (pairedRouter 4);
    "the router's NFQUEUE hook with af-packet suricata is rejected" = rejectedWith "needs othrys.services.suricata.mode" afPacketRouter;
    "crowdsec starts after the local resolver when othrys unbound is on" = builtins.elem "unbound.service" (crowdsecAfter true);
    "crowdsec is not ordered after a resolver the host does not run" = !(builtins.elem "unbound.service" (crowdsecAfter false));
    "on a router the bouncer's ipv4 table gains a forward hook on its set" = hasInfix "hook forward" (bouncerTable onRouter "crowdsec") && hasInfix "ip saddr @crowdsec-blacklists drop" (bouncerTable onRouter "crowdsec");
    "on a router the bouncer's ipv6 table gains a forward hook on its set" = hasInfix "ip6 saddr @crowdsec6-blacklists drop" (bouncerTable onRouter "crowdsec6");
    "the forward hook comes after the set it reads" = let
      c = bouncerTable onRouter "crowdsec";
      at = needle: builtins.stringLength (builtins.head (builtins.split needle c));
    in
      at "set crowdsec-blacklists" < at "hook forward";
    "off a router the bouncer keeps its input hook alone" = !hasInfix "hook forward" (bouncerTable alone "crowdsec");
    "traefik on the host adds its acquisition and collection" = builtins.elem "crowdsecurity/traefik" withTraefik.services.crowdsec.hub.collections && builtins.any (a: (a.labels.type or "") == "traefik") withTraefik.services.crowdsec.localConfig.acquisitions;
    "traefik on the host writes its access log for the parser" = withTraefik.services.traefik.staticConfigOptions.accessLog.format == "json";
    "without traefik nothing is added" = !builtins.any (a: (a.labels.type or "") == "traefik") alone.services.crowdsec.localConfig.acquisitions;
  }
