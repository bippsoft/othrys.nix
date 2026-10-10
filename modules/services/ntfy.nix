# modules/services/ntfy.nix
# Self-hosted ntfy push-notification server (services.ntfy-sh). The
# implementation-named server half of the notification pair, while the
# implementation-agnostic othrys.services.notify client dispatches to it (or
# to any other ntfy instance). Same relationship as headscale (server) and
# tailscale (client).
{
  config,
  lib,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.ntfy;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  loopback = cfg.listenAddress == "127.0.0.1" || cfg.listenAddress == "::1" || cfg.listenAddress == "localhost";
in {
  # ANCHOR: ntfy-options
  options.othrys.services.ntfy = {
    enable = lib.mkEnableOption "self-hosted ntfy push-notification server";

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address ntfy listens on. Loopback by default, expecting a reverse proxy in front; set to 0.0.0.0 to expose it directly.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
      description = "Port ntfy listens on.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open `port` in the firewall. Leave off when a reverse proxy fronts ntfy (the default).";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${cfg.listenAddress}:${toString cfg.port}";
      defaultText = lib.literalExpression ''"http://''${listenAddress}:''${port}"'';
      example = "https://ntfy.example.com";
      description = "Base URL (upstream requires it; used for attachments and web-app links). The loopback default serves internal notify hosts. Set the public URL when a reverse proxy fronts it.";
    };

    defaultAccess = lib.mkOption {
      type = lib.types.enum ["deny-all" "read-only" "write-only" "read-write"];
      default = "deny-all";
      description = ''
        What a client with no credentials may do on any topic
        (`auth-default-access`). ntfy's own default is `read-write`, which
        lets anyone who reaches the port publish to and read every topic,
        the alert topic included. Access is granted through `users`,
        `access` and `tokensFile`, or through `ntfy user` and `ntfy access`
        on the host.
      '';
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["alice:$2a$10$examplehash:user" "fleet:$2a$10$otherhash:user"];
      description = ''
        Accounts to provision, one `name:bcrypt-hash:role` entry each
        (`auth-users`). The hash comes from `ntfy user hash`, and the role is
        `user` or `admin`. A hash is not a password, so it may sit in the
        store; the password itself never goes here.
      '';
    };

    access = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["fleet:alerts:write-only" "alice:*:read-write"];
      description = "Access rules, one `user:topic:permission` entry each (`auth-access`), where the user is a name from `users` or `*` for anonymous clients.";
    };

    tokensFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."ntfy/tokens".path'';
      description = ''
        Environment file holding `NTFY_AUTH_TOKENS=user:tk_token:label,...`,
        which provisions access tokens for the accounts in `users`. A token
        is a credential, so it comes from a secrets provider and never from
        the store. The publishers then set `othrys.services.notify.tokenFile`
        to a file holding their token.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra services.ntfy-sh settings (server.yml), deep-merged over (and overriding) the generated config.";
    };
  };
  # ANCHOR_END: ntfy-options

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (!loopback && cfg.defaultAccess != "deny-all") "othrys.services.ntfy listens on ${cfg.listenAddress} with defaultAccess = \"${cfg.defaultAccess}\", so any client that reaches the port has that access to every topic.";

    # Message cache and auth database. The upstream unit runs with
    # DynamicUser + StateDirectory, so the real directory is under
    # /var/lib/private and /var/lib/ntfy-sh is systemd's symlink to it; a
    # bind mount at the symlink's path fought systemd's migration.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/private/ntfy-sh";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    # Tokens are credentials, so they reach ntfy through its environment
    # from a file the secrets provider writes, never through server.yml in
    # the store.
    systemd.services.ntfy-sh.serviceConfig.EnvironmentFile = lib.mkIf (cfg.tokensFile != null) [cfg.tokensFile];

    services.ntfy-sh = {
      enable = true;
      # lib.mkMerge rather than `//`. The union operator merges one level deep,
      # so a consumer setting a nested key under `settings` replaced the whole
      # generated subtree rather than adding to it.
      #
      # The priority sits on each generated leaf rather than on the attrset,
      # since a priority applies to a whole definition and one covering both
      # keys would be discarded entirely the moment a consumer names either one,
      # taking the other with it.
      #
      # mkOverride 900 rather than mkDefault, and the difference is a real
      # conflict. Upstream services.ntfy-sh defines settings.listen-http at
      # mkDefault priority itself, and two definitions at the same priority with
      # different values are an evaluation error, so any host that moved
      # listenAddress off loopback collided with upstream. 900 beats upstream's
      # 1000 and still loses to a consumer's plain definition at 100, so these
      # stay overridable without ever tying.
      settings = lib.mkMerge [
        {
          listen-http = lib.mkOverride 900 "${cfg.listenAddress}:${toString cfg.port}";
          base-url = lib.mkOverride 900 cfg.baseUrl;
          auth-default-access = lib.mkOverride 900 cfg.defaultAccess;
        }
        (lib.mkIf (cfg.users != []) {auth-users = cfg.users;})
        (lib.mkIf (cfg.access != []) {auth-access = cfg.access;})
        cfg.settings
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
