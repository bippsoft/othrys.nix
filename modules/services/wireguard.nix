# modules/services/wireguard.nix
# Raw WireGuard interfaces for site-to-site links, exit nodes and peers
#
# For hosts where a coordination server (tailscale/headscale) is unwanted.
# Private keys are runtime secrets-provider paths, never inline values.
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

          mtu = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            example = 1280;
            description = "MTU of the interface in bytes. Null leaves the WireGuard default of 1420, which is too large where the path underneath carries less than 1500.";
          };

          fwMark = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "0x6e6978";
            description = "Firewall mark set on the encrypted packets this interface sends. Policy routing uses it to keep the tunnel's own packets out of the tunnel when `allowedIPs` covers the default route.";
          };

          table = lib.mkOption {
            type = lib.types.str;
            default = "main";
            example = "51820";
            description = "Routing table the routes for `allowedIPs` are added to, by name or number. Anything but `main` leaves the default route alone until an `ip rule` selects the table.";
          };

          allowedIPsAsRoutes = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Add a route for every peer's `allowedIPs` to `table`. Set to
              `false` where the routes are managed elsewhere, by a routing
              daemon or by the host's own rules, and `allowedIPs` should only
              say which sources a peer may send from.
            '';
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
                presharedKeyFile = lib.mkOption {
                  type = lib.types.nullOr othrysTypes.secretPath;
                  default = null;
                  example = lib.literalExpression ''config.sops.secrets."wireguard/wg0-psk".path'';
                  description = "Path to a runtime file holding the preshared key for this peer, from `wg genpsk` (a secrets-provider path). Both ends must hold the same key.";
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
        inherit (iface) privateKeyFile ips listenPort mtu fwMark table allowedIPsAsRoutes;
        peers = map (p:
          {
            inherit (p) publicKey allowedIPs;
          }
          // lib.optionalAttrs (p.endpoint != null) {inherit (p) endpoint;}
          // lib.optionalAttrs (p.persistentKeepalive != null) {inherit (p) persistentKeepalive;}
          // lib.optionalAttrs (p.presharedKeyFile != null) {inherit (p) presharedKeyFile;})
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
