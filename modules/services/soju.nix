# modules/services/soju.nix
# soju, an IRC bouncer, on loopback by default and reached over TLS directly or through Traefik
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.soju;
  traefik = config.othrys.services.traefik;
  othrysTypes = import ../lib/types.nix {inherit lib;};

  tlsSet = cfg.tls.certificateFile != null || cfg.tls.keyFile != null;
  tlsComplete = cfg.tls.certificateFile != null && cfg.tls.keyFile != null;

  # The service runs under DynamicUser, so it cannot read a certificate that
  # root or the ACME group owns. LoadCredential copies both files into the
  # service's credentials directory at start, readable by the dynamic user
  # alone. The copy is taken once per start, so a renewed certificate is read
  # at the next restart and not at a reload.
  credentials = "/run/credentials/soju.service";
in {
  # ANCHOR: soju-options
  options.othrys.services.soju = {
    enable = lib.mkEnableOption "the soju IRC bouncer";

    port = lib.mkOption {
      type = lib.types.port;
      default = 6667;
      description = ''
        Port of the plaintext listener on loopback, `irc+insecure://`, which
        a client on the same host uses and which Traefik forwards to. It is
        never opened in the firewall.
      '';
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      default =
        if cfg.traefik.enable && cfg.traefik.domain != null
        then cfg.traefik.domain
        else config.networking.hostName;
      defaultText = lib.literalExpression "traefik.domain when traefik.enable is on, config.networking.hostName otherwise";
      example = "irc.example.com";
      description = ''
        Name soju gives itself as an IRC server, in the prefix of its own
        messages and in its welcome replies. soju warns at start when the
        name has no dot. It is not compared with the TLS name a client uses.
      '';
    };

    messageStore = lib.mkOption {
      type = lib.types.enum ["db" "fs" "memory"];
      default = "db";
      description = ''
        Where soju keeps message history. `db` writes it to the same sqlite
        database that holds the accounts, `soju.db` in the state directory,
        and gives soju's message search. `fs` writes plain-text logs under
        `logs` in the state directory, and `memory` keeps nothing across a
        restart. Upstream NixOS defaults to `fs`, while soju itself
        defaults to `db`.
      '';
    };

    tls = {
      certificateFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = "/var/lib/acme/irc.example.com/fullchain.pem";
        description = ''
          Runtime path to the certificate chain for soju's own TLS listener,
          `ircs://` on port 6697. Set together with `tls.keyFile`. The file
          is loaded into the service as a credential, so it can stay owned
          by root. A renewed certificate is read at the next restart of
          `soju.service`.
        '';
      };

      keyFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = "/var/lib/acme/irc.example.com/key.pem";
        description = "Runtime path to the private key for `tls.certificateFile`.";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open port 6697 for soju's own TLS listener. It has an effect only
        with `tls.certificateFile` set. The plaintext listener is never
        opened, and the port Traefik listens on is opened by
        `othrys.services.traefik.tcpRouters.soju.openFirewall`.
      '';
    };

    traefik = {
      enable = lib.mkEnableOption ''
        a Traefik TCP router for soju. Traefik terminates TLS on port 6697
        with its ACME resolver and forwards to soju over `[::1]` with a PROXY
        protocol header, so soju sees each client's own address
      '';

      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "irc.example.com";
        description = ''
          Name clients connect to. Traefik requests its certificate and
          routes on it, and a client that sends no such name is not routed.
          It becomes the default of `hostName`.
        '';
      };
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = "max-user-networks 5";
      description = "Lines appended to `soju.conf`. See {manpage}`soju(1)` for the directives.";
    };
  };
  # ANCHOR_END: soju-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !tlsSet || tlsComplete;
        message = "othrys.services.soju: tls.certificateFile and tls.keyFile are set together or not at all.";
      }
      {
        assertion = !(cfg.traefik.enable && tlsSet);
        message = "othrys.services.soju: traefik.enable and tls.certificateFile both serve port 6697. Unset tls.certificateFile and tls.keyFile to let Traefik terminate TLS, or turn traefik.enable off.";
      }
      {
        assertion = !cfg.traefik.enable || cfg.traefik.domain != null;
        message = "othrys.services.soju: traefik.enable needs traefik.domain, the name clients connect to.";
      }
      {
        assertion = !cfg.traefik.enable || (traefik.enable && traefik.acme.enable);
        message = "othrys.services.soju: traefik.enable needs othrys.services.traefik.enable and othrys.services.traefik.acme.enable, since Traefik terminates TLS with its ACME resolver.";
      }
      # soju trusts a PROXY header by the peer's address, on every listener
      # at once. Traefik dials [::1] and ::1 is the only trusted peer, so a
      # header sent from 127.0.0.1, where a local client connects, is not
      # read. With IPv6 off, lo has no ::1 and Traefik reaches nothing.
      {
        assertion = !cfg.traefik.enable || config.networking.enableIPv6;
        message = "othrys.services.soju: traefik.enable forwards to soju over [::1], which networking.enableIPv6 = false removes from lo. Turn IPv6 back on, or turn traefik.enable off.";
      }
    ];

    services.soju = {
      enable = true;
      listen =
        ["irc+insecure://127.0.0.1:${toString cfg.port}"]
        ++ lib.optional cfg.traefik.enable "irc+insecure://[::1]:${toString cfg.port}"
        ++ lib.optional tlsComplete "ircs://:6697";
      inherit (cfg) hostName extraConfig;
      messageStoreDriver = cfg.messageStore;
      # soju parses each value as a CIDR, so a bare ::1 stops it at start.
      acceptProxyIP = lib.optional cfg.traefik.enable "::1/128";
      tlsCertificate = lib.mkIf tlsComplete "${credentials}/certificate";
      tlsCertificateKey = lib.mkIf tlsComplete "${credentials}/key";
    };

    systemd.services.soju.serviceConfig.LoadCredential = lib.mkIf tlsComplete [
      "certificate:${cfg.tls.certificateFile}"
      "key:${cfg.tls.keyFile}"
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.openFirewall && tlsComplete) [6697];

    othrys.services.traefik.tcpRouters.soju = lib.mkIf cfg.traefik.enable {
      entryPoint = {
        name = "ircs";
        address = ":6697";
      };
      inherit (cfg.traefik) domain;
      backend = "[::1]:${toString cfg.port}";
      proxyProtocol = 2;
    };

    # DynamicUser puts the state directory at /var/lib/private/soju and makes
    # /var/lib/soju systemd's symlink to it, so the real directory is the one
    # persisted, as for ntfy. The database holds the accounts and the
    # passwords soju sends to the networks it joins.
    othrys.internal.persist."services.soju" = {
      directories = [
        {
          directory = "/var/lib/private/soju";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };
  };
}
