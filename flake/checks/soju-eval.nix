# flake/checks/soju-eval.nix
# CORE. What the soju module hands services.soju, systemd, the firewall,
# Traefik's TCP routers and the persistence registry, read back from
# evaluated hosts. Upstream's own defaults listen on :6697 with no TLS pair,
# which soju refuses at start, and keep history in plain files, so each
# value the module replaces is compared with a literal here. The generated
# soju.conf is read as the text of its writeText derivation, which needs no
# build. Every refusal is matched by a fragment of its message.
{
  lib,
  hostConfig,
  impermanenceModules,
  mkExpectations,
  rejectedWith,
  bootBase,
}: let
  # A host name with no dot, so a default that took it from anywhere but
  # networking.hostName shows.
  base = {
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
    networking.hostName = "bouncer";
  };
  host = modules: hostConfig ([bootBase base] ++ modules);
  sojuWith = settings: {othrys.services.soju = {enable = true;} // settings;};
  traefikWith = settings: {othrys.services.traefik = settings;};

  # ACME as the Traefik check sets it, which the TCP router needs to
  # terminate TLS.
  traefikOn = {
    enable = true;
    acme = {
      enable = true;
      email = "alice@example.com";
      dnsProvider = "cloudflare";
    };
    environmentFiles = ["/run/secrets/traefik-env"];
  };
  proxied.traefik = {
    enable = true;
    domain = "irc.example.com";
  };
  pair = {
    certificateFile = "/run/secrets/soju/cert.pem";
    keyFile = "/run/secrets/soju/key.pem";
  };

  off = host [];
  defaults = host [(sojuWith {})];
  fs = host [(sojuWith {messageStore = "fs";})];
  extra = host [(sojuWith {extraConfig = "max-user-networks 5";})];
  tls = host [(sojuWith {tls = pair;})];
  tlsOpen = host [
    (sojuWith {
      tls = pair;
      openFirewall = true;
    })
  ];
  plainOpen = host [(sojuWith {openFirewall = true;})];
  routed = host [(sojuWith proxied) (traefikWith traefikOn)];
  routed6680 = host [(sojuWith (proxied // {port = 6680;})) (traefikWith traefikOn)];

  # Refusals.
  halfPair = host [(sojuWith {tls.certificateFile = pair.certificateFile;})];
  routedWithTls = host [(sojuWith (proxied // {tls = pair;})) (traefikWith traefikOn)];
  noDomain = host [(sojuWith {traefik.enable = true;}) (traefikWith traefikOn)];
  traefikOff = host [(sojuWith proxied)];
  acmeOff = host [(sojuWith proxied) (traefikWith {enable = true;})];
  noIPv6 = host [(sojuWith proxied) (traefikWith traefikOn) {networking.enableIPv6 = false;}];

  # No disk layout is imported, so the wipe is given its device by hand and
  # the two volumes impermanence marks as needed for boot are named.
  impermanent = {
    imports = [impermanenceModules];
    fileSystems = {
      "/nix" = {
        device = "/dev/disk/by-label/nix";
        fsType = "btrfs";
      };
      "/persist" = {
        device = "/dev/disk/by-label/persist";
        fsType = "btrfs";
      };
    };
    othrys.system.impermanence = {
      enable = true;
      device = "/dev/disk/by-partlabel/root";
    };
  };
  wiped = host [impermanent (sojuWith {})];
  wipedOff = host [impermanent];
  entriesOf = cfg: cfg.environment.persistence.${cfg.othrys.system.impermanence.persistRoot}.directories;
  pathOf = entry: entry.dirPath or entry.directory;
  persisted = path: cfg: builtins.any (entry: pathOf entry == path) (entriesOf cfg);
  ownedBy = path: cfg:
    builtins.any (entry: pathOf entry == path && entry.user == "root" && entry.group == "root" && entry.mode == "0700") (entriesOf cfg);

  soju = cfg: cfg.services.soju;
  unit = cfg: cfg.systemd.services.soju.serviceConfig;
  ports = cfg: cfg.networking.firewall.allowedTCPPorts;
  opens = port: cfg: builtins.elem port (ports cfg);
  configLines = cfg: lib.splitString "\n" (soju cfg).configFile.text;
  hasLine = line: cfg: builtins.elem line (configLines cfg);
  hasTlsLine = cfg: builtins.any (lib.hasPrefix "tls ") (configLines cfg);
  router = routed.othrys.services.traefik.tcpRouters.soju;
  dynamicTcp = routed.services.traefik.dynamicConfigOptions.tcp;
  accepted = cfg: !rejectedWith "othrys.services.soju" cfg;
in
  mkExpectations "othrys-eval-soju" {
    # Absent case.
    "with the module off soju is not enabled" = !(soju off).enable;
    "with the module off no TCP router is written" = !(off.othrys.services.traefik.tcpRouters ? soju);
    "with the module off nothing is persisted for soju" = !(persisted "/var/lib/private/soju" wipedOff);

    # Defaults.
    "the default host trips no soju assertion" = accepted defaults;
    "the default host listens in plaintext on 127.0.0.1:6667 alone" = (soju defaults).listen == ["irc+insecure://127.0.0.1:6667"];
    "history is kept in the database by default" = (soju defaults).messageStoreDriver == "db";
    "no proxy is trusted by default" = (soju defaults).acceptProxyIP == [];
    "no TLS certificate is set by default" = (soju defaults).tlsCertificate == null && (soju defaults).tlsCertificateKey == null;
    "no credential is loaded into the unit by default" = !((unit defaults) ? LoadCredential);
    "the default host opens neither 6667 nor 6697" = !(opens 6667 defaults) && !(opens 6697 defaults);
    "the default host writes no TCP router" = !(defaults.othrys.services.traefik.tcpRouters ? soju);
    "the server name defaults to networking.hostName" = (soju defaults).hostName == "bouncer";
    "the generated config names the loopback listener" = hasLine "listen irc+insecure://127.0.0.1:6667" defaults;
    "the generated config names the host and the database store" = hasLine "hostname bouncer" defaults && hasLine "message-store db" defaults;
    "the generated config carries no tls line by default" = !(hasTlsLine defaults);

    # Persistence.
    "the impermanent host evaluates" = wiped.system.build.toplevel.drvPath != null;
    "the DynamicUser state directory is persisted for root at mode 0700" = ownedBy "/var/lib/private/soju" wiped;
    "the /var/lib/soju symlink is not persisted" = !(persisted "/var/lib/soju" wiped);

    # Message store.
    "messageStore = fs reaches messageStoreDriver" = (soju fs).messageStoreDriver == "fs";
    "extraConfig reaches the generated config" = hasLine "max-user-networks 5" extra;

    # Soju's own TLS listener.
    "a TLS pair trips no soju assertion" = accepted tls;
    "a TLS pair adds the ircs listener on 6697" = (soju tls).listen == ["irc+insecure://127.0.0.1:6667" "ircs://:6697"];
    "the certificate is read from the credentials directory" = (soju tls).tlsCertificate == "/run/credentials/soju.service/certificate";
    "the key is read from the credentials directory" = (soju tls).tlsCertificateKey == "/run/credentials/soju.service/key";
    "the unit loads both files as credentials" = (unit tls).LoadCredential == ["certificate:/run/secrets/soju/cert.pem" "key:/run/secrets/soju/key.pem"];
    "the generated config names both credential paths" = hasLine "tls /run/credentials/soju.service/certificate /run/credentials/soju.service/key" tls;
    "a TLS pair alone opens no port" = !(opens 6697 tls) && !(opens 6667 tls);
    "openFirewall with a TLS pair opens 6697 and not 6667" = opens 6697 tlsOpen && !(opens 6667 tlsOpen);
    "openFirewall without a TLS pair opens nothing" = !(opens 6697 plainOpen) && !(opens 6667 plainOpen);

    # Behind Traefik.
    "the routed host trips no soju assertion" = accepted routed;
    "the routed host trips no traefik assertion" = !rejectedWith "othrys.services.traefik" routed;
    "behind Traefik soju listens on both loopback addresses" = (soju routed).listen == ["irc+insecure://127.0.0.1:6667" "irc+insecure://[::1]:6667"];
    "behind Traefik only ::1 may send a PROXY header" = (soju routed).acceptProxyIP == ["::1/128"];
    "behind Traefik the server name is the domain" = (soju routed).hostName == "irc.example.com";
    "behind Traefik the generated config trusts ::1 and names the domain" = hasLine "accept-proxy-ip ::1/128" routed && hasLine "hostname irc.example.com" routed;
    "behind Traefik soju loads no credential" = !((unit routed) ? LoadCredential) && (soju routed).tlsCertificate == null;
    "the router listens on the ircs entrypoint" = router.entryPoint.name == "ircs";
    "the router's entrypoint is on 6697" = router.entryPoint.address == ":6697";
    "the router answers to the domain" = router.domain == "irc.example.com";
    "the router forwards to soju over ::1" = router.backend == "[::1]:6667";
    "the router sends PROXY protocol version 2" = router.proxyProtocol == 2;
    "Traefik's dynamic config carries the soju router on ircs" = dynamicTcp.routers.soju.entryPoints == ["ircs"];
    "Traefik's dynamic config matches the domain by SNI" = dynamicTcp.routers.soju.rule == "HostSNI(`irc.example.com`)";
    "Traefik's static config binds ircs on 6697" = routed.services.traefik.staticConfigOptions.entryPoints.ircs.address == ":6697";
    "Traefik opens 6697 for the router and 6667 stays closed" = opens 6697 routed && !(opens 6667 routed);
    "a non-default port moves both loopback listeners" = (soju routed6680).listen == ["irc+insecure://127.0.0.1:6680" "irc+insecure://[::1]:6680"];
    "a non-default port moves the router's backend" = routed6680.othrys.services.traefik.tcpRouters.soju.backend == "[::1]:6680";

    # Refusals.
    "half a TLS pair is refused" = rejectedWith "set together or not at all" halfPair;
    "traefik.enable beside a TLS pair is refused" = rejectedWith "both serve port 6697" routedWithTls;
    "traefik.enable without a domain is refused" = rejectedWith "needs traefik.domain" noDomain;
    "traefik.enable with othrys Traefik off is refused" = rejectedWith "needs othrys.services.traefik.enable" traefikOff;
    "traefik.enable with ACME off is refused" = rejectedWith "needs othrys.services.traefik.enable" acmeOff;
    "traefik.enable with IPv6 off is refused" = rejectedWith "removes from lo" noIPv6;
  }
