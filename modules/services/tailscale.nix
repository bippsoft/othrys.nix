# modules/services/tailscale.nix
# Tailscale VPN mesh networking (Headscale ready)
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
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.tailscale;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  router = config.othrys.services.router;
in {
  # ANCHOR: tailscale-options
  options.othrys.services.tailscale = {
    enable = lib.mkEnableOption "Tailscale VPN mesh networking";

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      description = "Path to auth key file for automatic registration.";
    };

    baseURL = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Control server the node registers with, passed as `--login-server`
        to `tailscale up` by the automatic registration, which `authKeyFile`
        turns on. A host registered by hand passes the same URL to
        `tailscale up` itself, and the module warns when this is set with no
        key file so that is not forgotten.
      '';
      example = "https://headscale.example.com";
    };

    ssh = lib.mkEnableOption "Tailscale SSH server (note: bypasses OpenSSH hardening and fail2ban)";

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Pass --accept-routes: install subnet routes advertised by OTHER
        tailnet nodes. A trust decision, since a compromised or misconfigured
        peer can redirect this host's traffic, which is why it is off until a
        host that needs advertised subnets turns it on.
      '';
    };

    operator = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alice";
      description = ''
        User allowed to drive `tailscale` without root, passed as
        `--operator`. Null leaves the CLI to root.
      '';
    };

    acceptDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pass --accept-dns=true: let the tailnet control the host's DNS
        configuration (MagicDNS). Set to false on hosts running their own
        resolver (unbound, the router module) or needing split-horizon DNS, since
        tailnet DNS would override it.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the Tailscale UDP port for direct (non-relayed) connections.";
    };

    ephemeral = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Register as an ephemeral node (deregistered when offline). Usually
        false for persistent machines. Applies to a node on Tailscale's own
        control plane, where it is a parameter of an OAuth client key; with
        `baseURL` set, the pre-auth key minted on that server decides.
      '';
    };
  };

  # ANCHOR_END: tailscale-options

  config = lib.mkIf cfg.enable {
    # On a router the global port list reaches every interface but the WAN,
    # and a direct path from a peer on the internet arrives on the WAN, so the
    # port is opened there by name as well.
    networking.firewall.interfaces = lib.mkIf (cfg.openFirewall && router.enable) {
      ${router.wan.interface}.allowedUDPPorts = [41641];
    };

    # Persistence for Tailscale state (node keys, etc.)
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
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
