# modules/services/ddns.nix
# Dynamic DNS updates via inadyn
#
# Keeps hostnames pointing at a dynamic residential IP (pairs with the Traefik
# DNS-01 ACME setup). Credentials arrive as an inadyn include snippet from a
# secrets provider (the file carries `password = ...` in inadyn.conf syntax),
# never inline.
{
  config,
  lib,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.ddns;

  # The provider names and aliases registered by plugins/*.c in the inadyn
  # 2.13.0 source, the release nixpkgs packages, with the `ipv6@` variants
  # some plugins clone from their `default@` name. `inadyn -L` prints the
  # same list. The list in inadyn.conf(5) is shorter than what the plugins
  # register.
  registeredProviders = [
    "default@3322.org"
    "dyndns@3322.org"
    "ipv6@3322.org"
    "default@all-inkl.com"
    "ipv6@all-inkl.com"
    "default@changeip.com"
    "default@cloudflare.com"
    "ipv6@cloudflare.com"
    "default@cloudxns.net"
    "default@core-networks.de"
    "ipv6@core-networks.de"
    "default@ddnss.de"
    "default@desec.io"
    "ipv6@desec.io"
    "default@dhis.org"
    "ipv6@dhis.org"
    "default@dnsever.com"
    "default@dnsexit.com"
    "ipv6@dnsexit.com"
    "default@dnshome.de"
    "ipv6@dnshome.de"
    "default@dnsmadeeasy.com"
    "default@dnsmax.com"
    "default@dnsomatic.com"
    "ipv6@dnsomatic.com"
    "default@dnspod.cn"
    "ipv6@dnspod.cn"
    "default@do.de"
    "ipv6@do.de"
    "default@domaindiscount24.com"
    "default@domains.google.com"
    "ipv6@domains.google.com"
    "default@domene.shop"
    "default@domopoli"
    "ipv6@domopoli"
    "default@duckdns.org"
    "ipv6@duckdns.org"
    "default@duiadns.net"
    "ipv6@duiadns.net"
    "default@dy.fi"
    "ipv6@dy.fi"
    "default@dyndns.it"
    "default@dyndns.org"
    "default@dynu.com"
    "ipv6@dynu.com"
    "default@dynv6.com"
    "ipv4@dynv6.com"
    "ipv6@dynv6.com"
    "default@easydns.com"
    "ipv6@easydns.com"
    "default@freedns.afraid.org"
    "ipv6@freedns.afraid.org"
    "default@freemyip.com"
    "default@gira.de"
    "ipv6@gira.de"
    "default@goip.de"
    "ipv6@goip.de"
    "default@he.net"
    "dyndns@he.net"
    "ipv6@he.net"
    "ipv6tb@he.net"
    "default@infomaniak.com"
    "ipv6@infomaniak.com"
    "default@inwx.com"
    "ipv6@inwx.com"
    "default@ipv4.dynv6.com"
    "default@ipv64.net"
    "ipv4@ipv64.net"
    "ipv6@ipv64.net"
    "default@itsdns.de"
    "ipv6@itsdns.de"
    "default@joker.com"
    "default@loopia.com"
    "default@moniker.com"
    "default@mydns.jp"
    "ipv6@mydns.jp"
    "default@myonlineportal.net"
    "ipv6@myonlineportal.net"
    "default@namecheap.com"
    "default@no-ip.com"
    "ipv6@no-ip.com"
    "default@noip.com"
    "ipv6@noip.com"
    "ipv4@nsupdate.info"
    "ipv6@nsupdate.info"
    "default@opendns.com"
    "ipv6@opendns.com"
    "default@oray.com"
    "default@ovh.com"
    "ipv6@ovh.com"
    "default@pdd.yandex.ru"
    "default@porkbun.com"
    "ipv6@porkbun.com"
    "default@regfish.de"
    "ipv6@regfish.de"
    "default@schokokeks.org"
    "ipv6@schokokeks.org"
    "default@selfhost.de"
    "ipv6@selfhost.de"
    "default@simply.com"
    "default@sitelutions.com"
    "default@spdyn.de"
    "ipv6@spdyn.de"
    "default@strato.com"
    "ipv6@strato.com"
    "default@thatip.com"
    "default@tunnelbroker.net"
    "default@twodns.de"
    "default@udmedia.de"
    "ipv6@udmedia.de"
    "default@variomedia.de"
    "ipv6@variomedia.de"
    "default@zoneedit.com"
    "ipv6@zoneedit.com"
  ];
  # inadyn resolves a name it does not know exactly by substring, so the
  # bare service name after the `@` is accepted as well. Any other substring
  # is refused here, since a typo would otherwise reach the daemon and fail
  # at its first run.
  bareNames = map (n: lib.last (lib.splitString "@" n)) registeredProviders;
  providerNames = lib.unique (registeredProviders ++ bareNames);
in {
  # ANCHOR: ddns-options
  options.othrys.services.ddns = {
    enable = lib.mkEnableOption "dynamic DNS updates (inadyn)";

    provider = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum providerNames);
      default = null;
      defaultText = lib.literalMD "none, and an assertion rejects an unset value once the module is enabled";
      example = "cloudflare.com";
      description = ''
        DDNS provider, one of the names inadyn registers (`inadyn -L` lists
        them). Either the full name, such as `default@cloudflare.com` or
        `ipv6@dynv6.com`, or the service name after the `@`, which inadyn
        resolves to the first plugin that carries it. Must be set when this
        module is enabled.
      '';
    };

    hostnames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      defaultText = lib.literalMD "none, and an assertion rejects an empty list once the module is enabled";
      example = ["home.example.com"];
      description = "Hostnames to keep updated. Identity-shaped, set from the consuming host. Must be non-empty when this module is enabled.";
    };

    username = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "example.com";
      description = "Provider username/account (for Cloudflare: the zone name). Null for token-only providers.";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      defaultText = lib.literalMD "none, and an assertion rejects an unset value once the module is enabled";
      example = lib.literalExpression ''config.sops.secrets."ddns/credentials".path'';
      description = ''
        Path to a runtime file included into the provider block, since inadyn.conf
        syntax, typically a single `password = <token>` line. A
        secrets-provider path; never inline the token. Must be set when this
        module is enabled.

        inadyn opens the file at run time as its own user inside a private
        user namespace, so a file that is root-owned and mode 0400 is
        unreadable and the service fails at its first update. With sops-nix
        set `owner = "inadyn"` on the secret.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra per-provider inadyn settings merged into the provider block.";
    };
  };
  # ANCHOR_END: ddns-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.provider != null && cfg.hostnames != [] && cfg.credentialsFile != null;
        message = "othrys.services.ddns: set provider, hostnames, and credentialsFile (a secrets-provider path holding `password = ...`).";
      }
    ];

    # No guard on provider or credentialsFile, since the assertion above
    # already refuses a host that leaves either unset. A null provider is
    # an attribute name Nix drops, so the assertion is what the host sees.
    services.inadyn = {
      enable = true;
      settings.provider.${cfg.provider} =
        {
          hostname = cfg.hostnames;
          include = cfg.credentialsFile;
          ssl = true;
        }
        // lib.optionalAttrs (cfg.username != null) {inherit (cfg) username;}
        // cfg.extraSettings;
    };
  };
}
