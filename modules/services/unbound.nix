# modules/services/unbound.nix
# Unbound recursive DNS, a thin wrapper over services.unbound with helpers for
# binding interfaces, per-subnet access control, DNS-over-TLS upstream
# forwarding, and RPZ blocklists. Anything else goes through `settings`
# (freeform unbound.conf), deep-merged over the generated config.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.unbound;

  rpzType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "RPZ zone name.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        description = "URL of the RPZ blocklist to fetch.";
      };
    };
  };

  generated = lib.foldl' lib.recursiveUpdate {} [
    (lib.optionalAttrs (cfg.interfaces != []) {server.interface = cfg.interfaces;})
    (lib.optionalAttrs (cfg.accessControl != []) {server.access-control = cfg.accessControl;})
    (lib.optionalAttrs cfg.forwardTls.enable {
      forward-zone = [
        {
          name = ".";
          forward-tls-upstream = true;
          forward-addr = cfg.forwardTls.upstreams;
        }
      ];
    })
    (lib.optionalAttrs (cfg.rpz != []) {
      rpz = map (r: {inherit (r) name url;}) cfg.rpz;
    })
    cfg.settings
  ];
in {
  # ANCHOR: unbound-options
  options.othrys.services.unbound = {
    enable = lib.mkEnableOption "Unbound recursive DNS";

    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["10.0.0.1" "127.0.0.1"];
      description = "Addresses Unbound listens on (server.interface).";
    };

    accessControl = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["10.0.0.0/24 allow"];
      description = "server.access-control entries (subnet + action).";
    };

    forwardTls = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Forward all queries to the DoT upstreams over TLS (port 853), instead of recursing.";
      };

      upstreams = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "1.1.1.1@853#cloudflare-dns.com"
          "1.0.0.1@853#cloudflare-dns.com"
          "9.9.9.9@853#dns.quad9.net"
        ];
        description = "DoT upstream resolvers (addr@853#hostname).";
      };
    };

    rpz = lib.mkOption {
      type = lib.types.listOf rpzType;
      default = [];
      description = "RPZ blocklist zones (ad/malware blocking).";
      example = lib.literalExpression ''
        [{ name = "hagezi"; url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/pro.txt"; }]
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra unbound.conf settings, deep-merged over (and overriding) the generated config.";
    };
  };
  # ANCHOR_END: unbound-options

  config = lib.mkIf cfg.enable {
    services.unbound = {
      enable = true;
      settings = generated;
    };
  };
}
