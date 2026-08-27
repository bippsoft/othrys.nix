# modules/services/wireguard.nix
# Raw WireGuard interfaces for site-to-site links, exit nodes, and peers
# where a coordination server (tailscale/headscale) is unwanted. Private
# keys are runtime secrets-provider paths, never inline values.
{
  config,
  lib,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.wireguard;
in {
  # ANCHOR: wireguard-options
  options.othrys.services.wireguard = {
    enable = lib.mkEnableOption "raw WireGuard interfaces (coordination-server-free VPN links)";

    interfaces = lib.mkOption {
      default = {};
      description = "WireGuard interfaces (maps to networking.wireguard.interfaces).";
      example = lib.literalExpression ''
        {
          wg0 = {
            privateKeyFile = config.sops.secrets."wireguard/wg0".path;
            ips = ["10.100.0.2/24"];
            listenPort = 51820;
            openFirewall = true;
            peers = [
              {
                publicKey = "<peer public key>";
                allowedIPs = ["10.100.0.0/24"];
                endpoint = "vpn.example.com:51820";
                persistentKeepalive = 25;
              }
            ];
          };
        }
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          privateKeyFile = lib.mkOption {
            type = othrysTypes.secretPath;
            description = "Path to a runtime file holding the interface private key (a secrets-provider path).";
          };

          ips = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Addresses (CIDR) assigned to the interface.";
          };

          listenPort = lib.mkOption {
            type = lib.types.nullOr lib.types.port;
            default = null;
            description = "UDP listen port. Null picks a random port (fine for outbound-only peers).";
          };

          openFirewall = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Open listenPort in the firewall (requires listenPort).";
          };

          peers = lib.mkOption {
            default = [];
            description = "Peers for this interface.";
            type = lib.types.listOf (lib.types.submodule {
              options = {
                publicKey = lib.mkOption {
                  type = lib.types.str;
                  description = "Peer public key.";
                };
                allowedIPs = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  description = "Networks routed to (and accepted from) this peer.";
                };
                endpoint = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  example = "vpn.example.com:51820";
                  description = "Peer endpoint. Null for peers that dial in.";
                };
                persistentKeepalive = lib.mkOption {
                  type = lib.types.nullOr lib.types.ints.positive;
                  default = null;
                  example = 25;
                  description = "Keepalive interval in seconds (needed behind NAT).";
                };
              };
            });
          };
        };
      });
    };
  };
  # ANCHOR_END: wireguard-options

  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (name: iface: {
        assertion = !iface.openFirewall || iface.listenPort != null;
        message = "othrys.services.wireguard.interfaces.${name}: openFirewall requires listenPort.";
      })
      cfg.interfaces;

    networking.wireguard.interfaces =
      lib.mapAttrs (_: iface: {
        inherit (iface) privateKeyFile ips;
        inherit (iface) listenPort;
        peers = map (p:
          {
            inherit (p) publicKey allowedIPs;
          }
          // lib.optionalAttrs (p.endpoint != null) {inherit (p) endpoint;}
          // lib.optionalAttrs (p.persistentKeepalive != null) {inherit (p) persistentKeepalive;})
        iface.peers;
      })
      cfg.interfaces;

    networking.firewall.allowedUDPPorts = lib.concatLists (lib.mapAttrsToList (
        _: iface:
          lib.optional (iface.openFirewall && iface.listenPort != null) iface.listenPort
      )
      cfg.interfaces);
  };
}
