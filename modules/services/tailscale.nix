# modules/services/tailscale.nix
# Tailscale VPN mesh networking (Headscale ready)
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.tailscale;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.services.tailscale = {
    enable = lib.mkEnableOption "Tailscale VPN mesh networking";

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to auth key file for automatic registration.";
    };

    baseURL = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Base URL for Headscale server.";
      example = "https://headscale.example.com";
    };

    ssh = lib.mkEnableOption "Tailscale SSH server (note: bypasses OpenSSH hardening and fail2ban)";

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pass --accept-routes: install subnet routes advertised by OTHER
        tailnet nodes. A trust decision, since a compromised or misconfigured peer
        can redirect this host's traffic. Servers that don't need advertised
        subnets should set this to false.
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
      description = "Register as an ephemeral node (deregistered when offline). Usually false for persistent machines.";
    };
  };

  config = lib.mkIf cfg.enable {
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

      authKeyParameters = {
        inherit (cfg) ephemeral baseURL;
        preauthorized = true;
      };

      extraUpFlags =
        lib.optional cfg.acceptRoutes "--accept-routes"
        ++ ["--accept-dns=${lib.boolToString cfg.acceptDns}"]
        ++ lib.optional cfg.ssh "--ssh";
    };
  };
}
