# modules/services/tailscale.nixos.nix
# The NixOS implementation of othrys.services.tailscale
#
# Two of upstream's hooks carry the options here. `extraUpFlags` is passed to
# `tailscale up` by the autoconnect unit, which exists only with authKeyFile,
# so the login server goes there and a host registered by hand passes it to
# `tailscale up` itself. `extraSetFlags` is passed to `tailscale set` by a
# unit that runs on every host after the daemon is up, so the routing, DNS,
# SSH and operator settings apply however the host was registered.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.tailscale;
  router = config.othrys.services.router;
in {
  imports = [./tailscale.nix];

  config = lib.mkIf cfg.enable {
    # On a router the global port list reaches every interface but the WAN,
    # and a direct path from a peer on the internet arrives on the WAN, so the
    # port is opened there by name as well.
    networking.firewall.interfaces = lib.mkIf (cfg.openFirewall && router.enable) {
      ${router.wan.interface}.allowedUDPPorts = [41641];
    };

    # Persistence for Tailscale state (node keys, etc.)
    othrys.internal.persist."services.tailscale" = {
      directories = [
        {
          directory = "/var/lib/tailscale";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };
    services.tailscale = {
      enable = true;

      port = 41641;
      interfaceName = "tailscale0";
      inherit (cfg) openFirewall;
      useRoutingFeatures = "client";

      inherit (cfg) authKeyFile;

      # Upstream appends these to the key as a query string, which is the
      # form an OAuth client key on Tailscale's own control plane takes.
      # Headscale expects a bare key and refuses one with anything appended,
      # so with a control server of its own nothing is appended, and the
      # key's own settings decide. The control server itself is not a key
      # parameter and goes to `--login-server` below.
      authKeyParameters = lib.mkIf (cfg.baseURL == null) {
        inherit (cfg) ephemeral;
        preauthorized = true;
      };

      extraUpFlags = lib.optional (cfg.baseURL != null) "--login-server=${cfg.baseURL}";

      extraSetFlags =
        ["--accept-routes=${lib.boolToString cfg.acceptRoutes}"]
        ++ ["--accept-dns=${lib.boolToString cfg.acceptDns}"]
        ++ ["--ssh=${lib.boolToString cfg.ssh}"]
        ++ lib.optional (cfg.operator != null) "--operator=${cfg.operator}";
    };

    warnings = lib.optional (cfg.baseURL != null && cfg.authKeyFile == null) "othrys.services.tailscale: baseURL is set and authKeyFile is not, so nothing passes it to `tailscale up`. Either set authKeyFile for automatic registration, or run `tailscale up --login-server ${cfg.baseURL}` on the host by hand.";
  };
}
