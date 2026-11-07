# modules/services/tailscale.nix
# Tailscale VPN mesh networking (Headscale ready)
{lib, ...}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
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
}
