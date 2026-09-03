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
  cfg = config.othrys.services.ntfy;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
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

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra services.ntfy-sh settings (server.yml), deep-merged over (and overriding) the generated config.";
    };
  };
  # ANCHOR_END: ntfy-options

  config = lib.mkIf cfg.enable {
    # Message cache and auth database.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/ntfy-sh";
          user = "ntfy-sh";
          group = "ntfy-sh";
          mode = "0700";
        }
      ];
    };

    services.ntfy-sh = {
      enable = true;
      # lib.mkMerge rather than `//`. The union operator merges one level deep,
      # so a consumer setting a nested key under `settings` replaced the whole
      # generated subtree rather than adding to it.
      #
      # mkDefault sits on each generated leaf rather than on the attrset. A
      # priority applies to a whole definition, so one mkDefault covering both
      # keys would be discarded entirely the moment a consumer names either one,
      # taking the other with it. Per leaf, each competes on its own and a
      # consumer setting base-url still gets the generated listen-http.
      #
      # Without the defaults, two normal-priority definitions of the same leaf
      # collide, which would make `settings.base-url` an evaluation error rather
      # than the override the description promises. lib.mkForce is not a
      # workaround, since `settings` is attrsOf anything and that type discharges
      # priorities here, so a mkForce inside it never reaches services.ntfy-sh.
      settings = lib.mkMerge [
        {
          listen-http = lib.mkDefault "${cfg.listenAddress}:${toString cfg.port}";
          base-url = lib.mkDefault cfg.baseUrl;
        }
        cfg.settings
      ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
  };
}
