# modules/services/unbound.nix
# Unbound recursive DNS, a thin wrapper over services.unbound
#
# It adds helpers for binding interfaces, per-subnet access control,
# DNS-over-TLS upstream forwarding, and RPZ blocklists. Anything else goes
# through `settings` (freeform unbound.conf), deep-merged over the generated
# config.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.unbound;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  rpzType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "RPZ zone name.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        example = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/pro.txt";
        description = "URL of the RPZ blocklist to fetch. Must use `https://`, since the zone rewrites answers for every client.";
      };
    };
  };

  # Upstream's access-control default allows loopback alone, so a host that
  # binds a LAN address answers nothing on it until the subnet is allowed.
  # The default access list is derived from the listen addresses instead. It
  # holds loopback, then the /24 of each IPv4 address and the /64 of each IPv6
  # address, which is what a LAN interface usually carries. A wildcard, an
  # interface name, a link-local address or an IPv4-mapped one gives nothing
  # to derive, so those are skipped and the host sets accessControl itself.
  bareAddress = a: builtins.head (lib.splitString "@" a);
  isIPv4 = a: builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+" a != null;
  isIPv6 = a: lib.hasInfix ":" a && !lib.hasInfix "%" a;
  isLoopback = a: lib.hasPrefix "127." a || a == "::1";
  isWildcard = a: a == "0.0.0.0" || lib.hasPrefix "::" a;
  isLinkLocal = a: lib.hasPrefix "fe80:" (lib.toLower a) || lib.hasPrefix "169.254." a;
  subnetOf = a:
    if isIPv4 a
    then "${lib.concatStringsSep "." (lib.take 3 (lib.splitString "." a))}.0/24 allow"
    else let
      # The groups before a `::`, or all eight when the address has none.
      leading = lib.splitString ":" (builtins.head (lib.splitString "::" a));
    in "${lib.concatStringsSep ":" (lib.take 4 leading)}::/64 allow";
  derivedAccessControl =
    ["127.0.0.0/8 allow" "::1/128 allow"]
    ++ lib.unique (map subnetOf (lib.filter (a: (isIPv4 a || isIPv6 a) && !isLoopback a && !isWildcard a && !isLinkLocal a) (map bareAddress cfg.interfaces)));

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
    # Each RPZ zone names a zonefile, relative to unbound's working directory,
    # which upstream sets to its state directory. Without one unbound keeps
    # the fetched zone in memory alone and fetches it again at every start.
    # With one it writes the zone to disk, loads it from there on the next
    # start, and only transfers again when the zone's refresh timer says so.
    (lib.optionalAttrs (cfg.rpz != []) {
      rpz =
        map (r: {
          inherit (r) name url;
          zonefile = "rpz-${r.name}.zone";
        })
        cfg.rpz;
      # An rpz block is served by the respip module, which Unbound's default
      # module-config leaves out, and unbound-checkconf rejects the config
      # rather than letting the daemon ignore the zone. mkDefault keeps a
      # host's own module-config, set through services.unbound.settings, on top.
      server.module-config = lib.mkDefault "respip validator iterator";
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
      description = "Addresses Unbound listens on (server.interface). Replaces upstream's loopback default, so list loopback when it should stay.";
    };

    accessControl = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = derivedAccessControl;
      defaultText = lib.literalMD "loopback, then the /24 of each IPv4 address and the /64 of each IPv6 address in `interfaces`";
      example = ["10.0.0.0/24 allow"];
      description = ''
        server.access-control entries (subnet + action). The default is
        derived from `interfaces`, so a host that listens on `10.0.0.1`
        answers `10.0.0.0/24` without further setup. A wildcard address or an
        interface name in `interfaces` derives nothing, so a host using one
        sets this itself.
      '';
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
      description = "RPZ blocklist zones (ad/malware blocking). Each `url` must use `https://`, and the respip module is added to server.module-config when the list is non-empty.";
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
    # A blocklist fetched over plain HTTP can be replaced on the wire, and
    # the zone then rewrites answers for every client of this resolver.
    assertions =
      map (r: {
        assertion = lib.hasPrefix "https://" r.url;
        message = "othrys.services.unbound.rpz: zone ${r.name} is fetched from ${r.url}. RPZ sources must use https://.";
      })
      cfg.rpz;

    # The state directory holds the root trust anchor that unbound-anchor
    # primes and the RPZ zonefiles named above. Upstream runs the daemon as
    # its own account with StateDirectory=unbound at the default 0755.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = config.services.unbound.stateDir;
          inherit (config.services.unbound) user group;
          mode = "0755";
        }
      ];
    };

    services.unbound = {
      enable = true;
      settings = generated;
    };
  };
}
