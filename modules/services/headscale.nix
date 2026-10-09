# modules/services/headscale.nix
# Headscale, the self-hosted Tailscale control server (the coordination plane the
# tailscale module can point its `baseURL` at). A thin wrapper over
# services.headscale with helpers for the public URL, listen socket, MagicDNS,
# and OIDC, while everything else goes through `settings` (freeform config.yaml),
# deep-merged over the generated config.
#
# An optional web UI (Headplane) is bundled under `ui`. Headplane was chosen over
# the SPA UIs (headscale-ui, headscale-admin) on two axes. Nixpkgs ships a native
# services.headplane module (no extra flake input, no browser bundle to serve),
# and it holds the Headscale API key, cookie secret, and OIDC secret SERVER-SIDE
# as file paths, since the SPAs park a full-privilege API key in browser localStorage.
# The nixpkgs module reads this Headscale instance's configFile/port/user, so the
# UI just needs `ui.enable` plus a couple of secret paths.
#
# Every credential-bearing field (oidc.clientSecretFile, ui.apiKeyFile,
# ui.cookieSecretFile, ui.oidc.clientSecretFile) is a runtime FILE PATH, not
# an inline value, so point it at a secret from a secrets provider (e.g. a
# sops secret: `config.sops.secrets."headscale/oidc-secret".path`). Never
# inline a secret or pass a /nix/store path, since those are world-readable.
# Both services run as the headscale user, so every such file has to be
# readable by it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.headscale;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  docs = config.othrys.services.docs;
  scrutiny = config.othrys.services.scrutiny;
  crowdsec = config.othrys.services.security.crowdsec;

  # The host part of serverUrl, which is what Headscale compares base_domain
  # against: it refuses a base_domain equal to that host or a suffix of it.
  serverHost = builtins.head (lib.splitString ":" (builtins.head (lib.splitString "/" (lib.removePrefix "https://" (lib.removePrefix "http://" cfg.serverUrl)))));
  baseDomainClashes = cfg.baseDomain != null && cfg.baseDomain != "" && (serverHost == cfg.baseDomain || lib.hasSuffix ".${cfg.baseDomain}" serverHost);

  # Upstream requires nameservers only when it overrides the clients' local
  # DNS, which it does by default.
  overrideLocalDns = cfg.settings.dns.override_local_dns or true;

  # The ACL policy as a file. An attribute set is written out as JSON, a path
  # is used as given. Neither is a secret, so the store is the right place.
  policyFile =
    if builtins.isAttrs cfg.policy
    then pkgs.writeText "headscale-policy.json" (builtins.toJSON cfg.policy)
    else cfg.policy;

  # Every account at the issuer can register unless one of these narrows it.
  oidcRestricted = cfg.oidc.allowedDomains != [] || cfg.oidc.allowedUsers != [] || cfg.oidc.allowedGroups != [];

  # nixpkgs' services.headplane already defaults headscale.url (local API),
  # public_url (= server_url), and config_path (= this instance's configFile), so
  # we only set what it cannot infer, meaning the listen socket, the API key
  # and OIDC.
  uiSettings = lib.foldl' lib.recursiveUpdate {} [
    {
      server = {
        inherit (cfg.ui) host port;
        cookie_secret_path = cfg.ui.cookieSecretFile;
      };
    }
    (lib.optionalAttrs (cfg.ui.configPath != null) {
      headscale.config_path = cfg.ui.configPath;
    })
    (lib.optionalAttrs cfg.ui.oidc.enable {
      oidc = {
        enabled = true;
        inherit (cfg.ui.oidc) issuer;
        client_id = cfg.ui.oidc.clientId;
        client_secret_path = cfg.ui.oidc.clientSecretFile;
        disable_api_key_login = cfg.ui.oidc.disableApiKeyLogin;
      };
      # Headplane's OIDC flow mints sessions with a Headscale API key, so reuse the
      # same key the UI authenticates to Headscale with. It now lives under
      # headscale.api_key_path (was the removed oidc.headscale_api_key_path).
      headscale.api_key_path = cfg.ui.apiKeyFile;
    })
    cfg.ui.settings
  ];

  generated = lib.foldl' lib.recursiveUpdate {} [
    {
      server_url = cfg.serverUrl;
      dns.magic_dns = cfg.magicDns;
    }
    (lib.optionalAttrs (cfg.baseDomain != null) {dns.base_domain = cfg.baseDomain;})
    (lib.optionalAttrs (cfg.nameservers != []) {dns.nameservers.global = cfg.nameservers;})
    (lib.optionalAttrs cfg.oidc.enable {
      oidc =
        {
          inherit (cfg.oidc) issuer;
          client_id = cfg.oidc.clientId;
          client_secret_path = cfg.oidc.clientSecretFile;
        }
        // lib.optionalAttrs (cfg.oidc.allowedDomains != []) {allowed_domains = cfg.oidc.allowedDomains;}
        // lib.optionalAttrs (cfg.oidc.allowedUsers != []) {allowed_users = cfg.oidc.allowedUsers;}
        // lib.optionalAttrs (cfg.oidc.allowedGroups != []) {allowed_groups = cfg.oidc.allowedGroups;};
    })
    (lib.optionalAttrs (cfg.policy != null) {
      policy = {
        mode = "file";
        path = toString policyFile;
      };
    })
    cfg.settings
  ];
in {
  imports = [
    (lib.mkRemovedOptionModule ["othrys" "services" "headscale" "ui" "agent" "enable"] "The Headplane agent needs a tailnet pre-auth key that nixpkgs' services.headplane cannot be handed, so the option never started a working agent and has been removed.")
    (lib.mkRemovedOptionModule ["othrys" "services" "headscale" "ui" "agent" "preAuthKeyFile"] "Removed with othrys.services.headscale.ui.agent.enable.")
  ];

  # ANCHOR: headscale-options
  options.othrys.services.headscale = {
    enable = lib.mkEnableOption "Headscale self-hosted Tailscale control server";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://headscale.example.com";
      description = ''
        Public URL clients register against (settings.server_url). Mandatory, with
        no default.
        Must resolve to this host (typically via a TLS-terminating reverse proxy)
        and must differ from the MagicDNS `baseDomain`.
      '';
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address Headscale listens on. Defaults to loopback, expecting a reverse proxy in front; set to 0.0.0.0 to expose it directly.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port Headscale listens on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall. Leave off when a reverse proxy fronts Headscale (the default).";
    };

    magicDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable MagicDNS (settings.dns.magic_dns).";
    };

    baseDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "tailnet.example.com";
      description = "MagicDNS base domain (settings.dns.base_domain), an FQDN without a trailing dot. Must differ from the `serverUrl` host. Null leaves it unset.";
    };

    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["1.1.1.1" "9.9.9.9"];
      description = "Global nameservers pushed to clients (settings.dns.nameservers.global).";
    };

    oidc = {
      enable = lib.mkEnableOption "OIDC authentication for node registration";

      issuer = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "https://auth.example.com/realms/main";
        description = "OIDC issuer URL (settings.oidc.issuer).";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "headscale";
        description = "OIDC client ID (settings.oidc.client_id).";
      };

      clientSecretFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."headscale/oidc-secret".path'';
        description = ''
          Path to a runtime file holding the OIDC client secret (a
          secrets-provider path). Never inline the secret. Headscale reads it
          as its own user, so the file must be readable by `headscale`; with
          sops-nix that is `owner = "headscale"` on the secret.
        '';
      };

      allowedDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["example.com"];
        description = "Email domains whose accounts may register (settings.oidc.allowed_domains).";
      };

      allowedUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["alice@example.com"];
        description = "Accounts that may register (settings.oidc.allowed_users).";
      };

      allowedGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["tailnet"];
        description = ''
          Groups whose members may register (settings.oidc.allowed_groups).
          The issuer has to put a groups claim in the token for this to apply.

          With none of the three lists set, every account the issuer knows
          can register a node, and the module warns about it.
        '';
      };
    };

    policy = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path (lib.types.attrsOf lib.types.anything));
      default = null;
      example = lib.literalExpression ''
        {
          acls = [
            {
              action = "accept";
              src = ["group:admins"];
              dst = ["*:*"];
            }
          ];
          groups."group:admins" = ["alice@example.com"];
        }
      '';
      description = ''
        The tailnet ACL policy (settings.policy), as a path to a HuJSON file
        or as an attribute set written out as JSON. Null leaves Headscale on
        its default, which lets every node reach every other node. The
        policy is not a secret and lives in the store.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra config.yaml settings, deep-merged over (and overriding) the generated config.";
    };

    ui = {
      enable = lib.mkEnableOption "Headplane web UI for this Headscale instance (server-side API-key custody, OIDC SSO)";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        defaultText = lib.literalExpression "pkgs.headplane";
        description = "Headplane package override. Null uses pkgs.headplane (the nixpkgs default for services.headplane).";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address Headplane listens on. Loopback by default, expecting a reverse proxy in front.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Port Headplane listens on.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the UI `port` in the firewall. Leave off when a reverse proxy fronts Headplane (the default).";
      };

      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."headscale/headplane-apikey".path'';
        description = ''
          Path to a runtime file holding a Headscale API key (from
          `headscale apikeys create`). Written to Headplane's
          `headscale.api_key_path`, which it uses server-side to mint OIDC
          sessions, so it is required when `ui.oidc` is enabled. Without it,
          Headplane authenticates via its in-browser API-key login and this
          is unused. Use a secrets-provider path readable by the `headscale`
          user, which Headplane runs as.
        '';
      };

      cookieSecretFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."headscale/headplane-cookie".path'';
        description = "Path to a runtime file holding the cookie-signing secret (a random string). Required when the UI is enabled. Use a secrets-provider path readable by the `headscale` user.";
      };

      configPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        defaultText = lib.literalExpression "config.services.headscale.configFile";
        description = "Path to the Headscale config.yaml Headplane reads. Null uses the NixOS-generated config file for this instance.";
      };

      oidc = {
        enable = lib.mkEnableOption "OIDC SSO for Headplane admin login";

        issuer = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "https://auth.example.com/realms/main";
          description = "OIDC issuer URL for Headplane login.";
        };

        clientId = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "headplane";
          description = "OIDC client ID for Headplane.";
        };

        clientSecretFile = lib.mkOption {
          type = lib.types.nullOr othrysTypes.secretPath;
          default = null;
          example = lib.literalExpression ''config.sops.secrets."headscale/headplane-oidc".path'';
          description = "Path to a runtime file holding Headplane's OIDC client secret. Never inline the secret. Readable by the `headscale` user.";
        };

        disableApiKeyLogin = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Disable the fallback API-key login form once OIDC is configured, enforcing SSO-only admin access.";
        };
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        description = "Extra Headplane settings, deep-merged over (and overriding) the generated config.";
      };
    };
  };
  # ANCHOR_END: headscale-options

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.oidc.enable || (cfg.oidc.issuer != "" && cfg.oidc.clientId != "" && cfg.oidc.clientSecretFile != null);
          message = "othrys.services.headscale.oidc: set issuer, clientId, and clientSecretFile (a secrets-provider path) when OIDC is enabled.";
        }
        {
          assertion = !baseDomainClashes;
          message = "othrys.services.headscale: baseDomain (MagicDNS) must not be the serverUrl host or a suffix of it; Headscale rejects that. A base domain that merely shares letters with the host, such as example.com beside hs.notexample.com, is fine.";
        }
        # Surface upstream's requirements with an actionable message, or the
        # eval fails deep inside the nixpkgs headscale module. MagicDNS needs
        # a base domain, and overriding the clients' DNS, which is on by
        # default, needs nameservers to hand them.
        {
          assertion = !cfg.magicDns || cfg.baseDomain != null;
          message = "othrys.services.headscale: MagicDNS (magicDns, on by default) requires baseDomain. Set it, or set magicDns = false.";
        }
        {
          assertion = !overrideLocalDns || cfg.nameservers != [];
          message = "othrys.services.headscale: overriding the clients' DNS (settings.dns.override_local_dns, on by default) requires at least one entry in nameservers. Set one, or set settings.dns.override_local_dns = false.";
        }
        # Three services default to 8080 on loopback, and whichever starts
        # second fails to bind.
        {
          assertion = !(scrutiny.enable && scrutiny.port == cfg.port);
          message = "othrys.services.headscale: port ${toString cfg.port} is also othrys.services.scrutiny.port. Give one of them another port.";
        }
        {
          assertion = !(crowdsec.enable && cfg.port == 8080);
          message = "othrys.services.headscale: port 8080 is where the CrowdSec local API listens on this host. Give Headscale another port.";
        }
      ];

      warnings = lib.optional (cfg.oidc.enable && !oidcRestricted) "othrys.services.headscale: OIDC is on with none of oidc.allowedDomains, allowedUsers or allowedGroups set, so every account at ${cfg.oidc.issuer} can register a node on this tailnet.";

      # Node keys, the SQLite database, and generated DERP/noise keys live here.
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        directories = [
          {
            directory = "/var/lib/headscale";
            user = "headscale";
            group = "headscale";
            # What upstream's StateDirectoryMode creates, so the CLI run by a
            # member of the headscale group keeps its access.
            mode = "0750";
          }
        ];
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

      services.headscale = {
        enable = true;
        inherit (cfg) address port;
        settings = generated;
      };
    }

    (lib.mkIf cfg.ui.enable {
      assertions = [
        {
          assertion = cfg.ui.cookieSecretFile != null;
          message = "othrys.services.headscale.ui: set cookieSecretFile (a secrets-provider path to a 32-char cookie-signing secret) when the UI is enabled.";
        }
        {
          assertion = !cfg.ui.oidc.enable || (cfg.ui.oidc.issuer != "" && cfg.ui.oidc.clientId != "" && cfg.ui.oidc.clientSecretFile != null && cfg.ui.apiKeyFile != null);
          message = "othrys.services.headscale.ui.oidc: set issuer, clientId, clientSecretFile, and apiKeyFile (the Headscale API key the OIDC flow mints sessions with), all secrets-provider paths, when the UI's OIDC login is enabled.";
        }
        {
          assertion = !(docs.enable && docs.port == cfg.ui.port);
          message = "othrys.services.headscale.ui: port ${toString cfg.ui.port} is also othrys.services.docs.port. Give one of them another port.";
        }
      ];

      # Headplane runs as the headscale user, and its state lives here.
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        directories = [
          {
            directory = "/var/lib/headplane";
            user = "headscale";
            group = "headscale";
            mode = "0700";
          }
        ];
      };

      networking.firewall.allowedTCPPorts = lib.mkIf cfg.ui.openFirewall [cfg.ui.port];

      services.headplane =
        {
          enable = true;
          settings = uiSettings;
        }
        // lib.optionalAttrs (cfg.ui.package != null) {inherit (cfg.ui) package;};
    })
  ]);
}
