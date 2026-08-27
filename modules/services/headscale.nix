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
# Every credential-bearing field (oidc.clientSecretFile,
# ui.apiKeyFile, ui.cookieSecretFile, ui.oidc.clientSecretFile,
# ui.agent.preAuthKeyFile) is a runtime FILE PATH, not an inline value, so point it
# at a secret from a secrets provider (e.g. a sops secret:
# `config.sops.secrets."headscale/oidc-secret".path`). Never inline a secret or
# pass a /nix/store path, since those are world-readable.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.headscale;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # nixpkgs' services.headplane already defaults headscale.url (local API),
  # public_url (= server_url), and config_path (= this instance's configFile), so
  # we only set what it cannot infer, meaning the listen socket, the API key, the agent,
  # and OIDC.
  uiSettings = lib.foldl' lib.recursiveUpdate {} [
    {
      server = {
        inherit (cfg.ui) host port;
        cookie_secret_path = cfg.ui.cookieSecretFile;
      };
    }
    # The agent submodule (integration.agent) is nullOr and defaults to null;
    # writing it at all, even with enabled = false, materializes it and trips
    # the upstream api_key_path assertion. So only emit it when the agent is on.
    # The agent authenticates to Headscale with an API key, now taken from
    # headscale.api_key_path (the settings-side pre-auth key field was removed).
    # The agent ALSO needs a tailnet pre-auth key to join the tailnet;
    # upstream passes that via the service environment, not settings, so wiring
    # ui.agent.preAuthKeyFile through systemd is a follow-up (agent stays off here).
    (lib.optionalAttrs cfg.ui.agent.enable {
      integration.agent.enabled = true;
      headscale.api_key_path = cfg.ui.apiKeyFile;
    })
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
      oidc = {
        inherit (cfg.oidc) issuer;
        client_id = cfg.oidc.clientId;
        client_secret_path = cfg.oidc.clientSecretFile;
      };
    })
    cfg.settings
  ];
in {
  # ANCHOR: headscale-options
  options.othrys.services.headscale = {
    enable = lib.mkEnableOption "Headscale self-hosted Tailscale control server";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://headscale.example.com";
      description = ''
        Public URL clients register against (settings.server_url). Required.
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
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."headscale/oidc-secret".path'';
        description = "Path to a runtime file holding the OIDC client secret (a secrets-provider path). Never inline the secret.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
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
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."headscale/headplane-apikey".path'';
        description = ''
          Path to a runtime file holding a Headscale API key (from
          `headscale apikeys create`). Written to Headplane's
          `headscale.api_key_path`, which it uses server-side both to mint OIDC
          sessions and for the agent integration, so it is required when
          `ui.oidc` or `ui.agent` is enabled. With neither, Headplane
          authenticates via its in-browser API-key login and this is unused.
          Use a secrets-provider path.
        '';
      };

      cookieSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."headscale/headplane-cookie".path'';
        description = "Path to a runtime file holding the cookie-signing secret (a random string). Required when the UI is enabled. Use a secrets-provider path.";
      };

      configPath = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        defaultText = lib.literalExpression "config.services.headscale.configFile";
        description = "Path to the Headscale config.yaml Headplane reads. Null uses the NixOS-generated config file for this instance.";
      };

      agent = {
        enable = lib.mkEnableOption "the Headplane agent integration (richer per-node data: OS, version). Off by default to keep the surface small";

        preAuthKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = lib.literalExpression ''config.sops.secrets."headscale/headplane-preauth".path'';
          description = "Path to a runtime file holding a Headscale pre-auth key the agent joins the tailnet with. Required when the agent is enabled. Use a secrets-provider path.";
        };
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
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = lib.literalExpression ''config.sops.secrets."headscale/headplane-oidc".path'';
          description = "Path to a runtime file holding Headplane's OIDC client secret. Never inline the secret.";
        };

        disableApiKeyLogin = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Disable the fallback API-key login form once OIDC is configured, enforcing SSO-only admin access.";
        };
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
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
          assertion = cfg.baseDomain == null || cfg.baseDomain == "" || !(lib.hasInfix cfg.baseDomain cfg.serverUrl);
          message = "othrys.services.headscale: baseDomain (MagicDNS) must differ from the serverUrl host; Headscale rejects a base_domain that is a suffix of server_url.";
        }
        # Surface upstream's requirements with an actionable message, since MagicDNS
        # (on by default) needs a base domain and global nameservers, or the
        # eval fails deep inside the nixpkgs headscale module.
        {
          assertion = !cfg.magicDns || (cfg.baseDomain != null && cfg.nameservers != []);
          message = "othrys.services.headscale: MagicDNS (magicDns, on by default) requires baseDomain and at least one entry in nameservers. Set both, or set magicDns = false.";
        }
      ];

      # Node keys, the SQLite database, and generated DERP/noise keys live here.
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
        directories = [
          {
            directory = "/var/lib/headscale";
            user = "headscale";
            group = "headscale";
            mode = "0700";
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
          assertion = !cfg.ui.agent.enable || (cfg.ui.apiKeyFile != null && cfg.ui.agent.preAuthKeyFile != null);
          message = "othrys.services.headscale.ui.agent: enabling the agent needs apiKeyFile (the Headscale API key it queries with, written to headscale.api_key_path) and preAuthKeyFile (the pre-auth key it joins the tailnet with), both secrets-provider paths.";
        }
      ];

      # Headplane runs as the headscale user, and its state (agent cache) lives here.
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
