# flake/checks/router-services.nix
# CORE. Two start-up defaults of the router's security services, read back from
# the evaluated host. Both failures they guard against only show on a host with
# a route out, which no VM test has, so they are pinned here.
{
  hostConfig,
  mkExpectations,
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

  suricata = settings:
    (host {
      othrys.services.suricata = {
        enable = true;
        mode = "nfqueue";
        inherit settings;
      };
    }).services.suricata.settings.app-layer.protocols;

  crowdsecAfter = unbound:
    (host {
      othrys.services.security.crowdsec = {
        enable = true;
        collections = [];
      };
      othrys.services.unbound.enable = unbound;
    }).systemd.services.crowdsec.after;
in
  mkExpectations "othrys-eval-router-services" {
    "suricata states modbus as off so suricata-update drops its rules" = (suricata {}).modbus.enabled == "no";
    "suricata states dnp3 as off so suricata-update drops its rules" = (suricata {}).dnp3.enabled == "no";
    "a host that turns a parser on keeps its value" = (suricata {app-layer.protocols.modbus.enabled = "yes";}).modbus.enabled == "yes";
    "the other protocol keeps its default beside an override" = (suricata {app-layer.protocols.modbus.enabled = "yes";}).dnp3.enabled == "no";
    "crowdsec starts after the local resolver when othrys unbound is on" = builtins.elem "unbound.service" (crowdsecAfter true);
    "crowdsec is not ordered after a resolver the host does not run" = !(builtins.elem "unbound.service" (crowdsecAfter false));
  }
