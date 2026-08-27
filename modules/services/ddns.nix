# modules/services/ddns.nix
# Dynamic DNS updates via inadyn, keeping hostnames pointing at a dynamic
# residential IP (pairs with the Traefik DNS-01 ACME setup). Credentials
# arrive as an inadyn include snippet from a secrets provider (the file
# carries `password = ...` in inadyn.conf syntax), never inline.
{
  config,
  lib,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.ddns;
in {
  # ANCHOR: ddns-options
  options.othrys.services.ddns = {
    enable = lib.mkEnableOption "dynamic DNS updates (inadyn)";

    provider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "cloudflare.com";
      description = "DDNS provider name as inadyn knows it (see inadyn.conf(5)). Required.";
    };

    hostnames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["home.example.com"];
      description = "Hostnames to keep updated. Identity-shaped, set from the consuming host. Required.";
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
      example = lib.literalExpression ''config.sops.secrets."ddns/credentials".path'';
      description = ''
        Path to a runtime file included into the provider block, since inadyn.conf
        syntax, typically a single `password = <token>` line. A
        secrets-provider path; never inline the token. Required.
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

    services.inadyn = lib.mkIf (cfg.provider != null && cfg.credentialsFile != null) {
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
