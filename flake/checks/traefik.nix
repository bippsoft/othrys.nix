# flake/checks/traefik.nix
# CORE. The Traefik TLS floor, security headers and TCP routers, read back
# from the configuration the module hands to services.traefik and from the
# firewall. One host takes every default with ACME on, one turns each default
# off, and one overrides a generated value through dynamicConfigOptions, which
# has to win. A fourth names a proxy in front and a log level, which reach the
# static configuration only when set. The tcpRouters hosts read back the
# entrypoint, router, service and servers transport each router writes, the
# port it opens, and the assertions that refuse a router without ACME, a
# shared port or entrypoint name, and a name or port the module keeps for
# itself.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
}: let
  hostOf = traefik:
    hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
        othrys.services.traefik = {enable = true;} // traefik;
      }
    ];
  traefikHost = traefik: (hostOf traefik).services.traefik;

  acme = {
    enable = true;
    email = "alice@example.com";
    dnsProvider = "cloudflare";
  };
  environmentFiles = ["/run/secrets/traefik-env"];

  defaults = traefikHost {
    inherit acme environmentFiles;
  };
  noAcme = traefikHost {};
  allOff = traefikHost {
    tls = {
      minVersion = null;
      sniStrict = false;
    };
    securityHeaders = {
      hstsSeconds = 0;
      contentTypeNosniff = false;
      frameOptions = null;
    };
  };
  overridden = traefikHost {
    dynamicConfigOptions = {
      tls.options.default.minVersion = "VersionTLS13";
      http.routers.app.rule = "Host(`app.example.com`)";
    };
  };

  proxied = traefikHost {
    forwardedHeaders.trustedIPs = ["192.0.2.0/24"];
    logLevel = "INFO";
  };
  entryPoints = host: host.staticConfigOptions.entryPoints;

  middleware = "othrys-security-headers";
  headersOf = host: host.dynamicConfigOptions.http.middlewares.${middleware}.headers;
  attached = host: host.staticConfigOptions.entryPoints.websecure.http.middlewares or [];

  # TCP routers. Every host here except the passthrough one has ACME on.
  soju = {
    entryPoint.address = ":6697";
    domain = "irc.example.com";
    backend = "[::1]:6667";
    proxyProtocol = 2;
  };
  withRouters = extra: tcpRouters:
    hostOf ({
        inherit acme environmentFiles tcpRouters;
      }
      // extra);

  sojuCfg = withRouters {} {inherit soju;};
  sojuHost = sojuCfg.services.traefik;
  sojuTcp = sojuHost.dynamicConfigOptions.tcp;

  renamed = (withRouters {} {soju = soju // {entryPoint = soju.entryPoint // {name = "ircs";};};}).services.traefik;

  noProxy = (withRouters {} {soju = soju // {proxyProtocol = null;};}).services.traefik;

  passthroughCfg = hostOf {
    tcpRouters.soju = {
      entryPoint.address = ":6697";
      domain = "irc.example.com";
      backend = "[::1]:6697";
      passthrough = true;
    };
  };
  passthroughRouter = passthroughCfg.services.traefik.dynamicConfigOptions.tcp.routers.soju;

  portsOf = cfg: cfg.networking.firewall.allowedTCPPorts;
  opens = port: cfg: builtins.elem port (portsOf cfg);
  routerOnly = withRouters {openFirewall = false;} {soju = soju // {openFirewall = true;};};
  routerClosed = withRouters {} {soju = soju // {openFirewall = false;};};
  routerDefaultClosed = withRouters {openFirewall = false;} {inherit soju;};

  # Refusals.
  terminatingNoAcme = hostOf {tcpRouters = {inherit soju;};};
  sharedPort = withRouters {} {
    inherit soju;
    other = soju // {entryPoint.address = "0.0.0.0:6697";};
  };
  sharedName = withRouters {} {
    a =
      soju
      // {
        entryPoint = {
          name = "ircs";
          address = ":6697";
        };
      };
    b =
      soju
      // {
        entryPoint = {
          name = "ircs";
          address = ":6698";
        };
      };
  };
  reservedName = withRouters {} {soju = soju // {entryPoint = soju.entryPoint // {name = "websecure";};};};
  on443 = withRouters {} {soju = soju // {entryPoint.address = ":443";};};
  on8080Insecure = withRouters {
    dashboard = {
      enable = true;
      insecure = true;
    };
  } {soju = soju // {entryPoint.address = ":8080";};};
  on8080Secure = withRouters {
    dashboard = {
      enable = true;
      insecure = false;
    };
  } {soju = soju // {entryPoint.address = ":8080";};};
in
  mkExpectations "othrys-eval-traefik" {
    "the default TLS floor is 1.2" = defaults.dynamicConfigOptions.tls.options.default.minVersion == "VersionTLS12";
    "sniStrict is on with ACME" = defaults.dynamicConfigOptions.tls.options.default.sniStrict;
    "sniStrict is off without ACME" = !noAcme.dynamicConfigOptions.tls.options.default.sniStrict;
    "HSTS defaults to one year" = (headersOf defaults).stsSeconds == 31536000;
    "HSTS leaves subdomains and preload alone" = !((headersOf defaults) ? stsIncludeSubdomains) && !((headersOf defaults) ? stsPreload);
    "nosniff is on" = (headersOf defaults).contentTypeNosniff;
    "frames are limited to the same origin" = (headersOf defaults).customFrameOptionsValue == "SAMEORIGIN";
    "the middleware is attached at websecure" = attached defaults == ["${middleware}@file"];
    "the ACME resolver survives next to the middleware" = defaults.staticConfigOptions.entryPoints.websecure.http.tls.certResolver == "letsencrypt";
    "minVersion = null leaves Traefik's default" = !(allOff.dynamicConfigOptions.tls.options.default ? minVersion);
    "sniStrict can be turned off" = !allOff.dynamicConfigOptions.tls.options.default.sniStrict;
    "with every header off no middleware is defined" = !(allOff.dynamicConfigOptions ? http);
    "with every header off nothing is attached" = attached allOff == [];
    "dynamicConfigOptions overrides a generated value" = overridden.dynamicConfigOptions.tls.options.default.minVersion == "VersionTLS13";
    "dynamicConfigOptions keeps the generated middleware" = (headersOf overridden).contentTypeNosniff;
    "no peer's forwarded headers are trusted by default" = !((entryPoints noAcme).web ? forwardedHeaders) && !((entryPoints noAcme).websecure ? forwardedHeaders);
    "trusted proxies reach both entrypoints" = (entryPoints proxied).web.forwardedHeaders.trustedIPs == ["192.0.2.0/24"] && (entryPoints proxied).websecure.forwardedHeaders.trustedIPs == ["192.0.2.0/24"];
    "the entrypoints keep their addresses beside the trusted proxies" = (entryPoints proxied).web.address == ":80" && (entryPoints proxied).websecure.address == ":443";
    "no log level is written by default" = !(noAcme.staticConfigOptions ? log);
    "logLevel reaches the static configuration" = proxied.staticConfigOptions.log.level == "INFO";
    "dynamicConfigOptions adds its own router" = overridden.dynamicConfigOptions.http.routers.app.rule == "Host(`app.example.com`)";

    # tcpRouters
    "with no tcpRouters no tcp configuration is written" = !(defaults.dynamicConfigOptions ? tcp) && !(noAcme.dynamicConfigOptions ? tcp);
    "the soju router with ACME trips no traefik assertion" = !rejectedWith "othrys.services.traefik" sojuCfg;
    "a TCP router writes its entrypoint at its address" = (entryPoints sojuHost).soju.address == ":6697";
    "a TCP router keeps the web and websecure entrypoints" = (entryPoints sojuHost).web.address == ":80" && (entryPoints sojuHost).websecure.address == ":443";
    "the TCP router listens on its own entrypoint" = sojuTcp.routers.soju.entryPoints == ["soju"];
    "the TCP router matches its domain by SNI" = sojuTcp.routers.soju.rule == "HostSNI(`irc.example.com`)";
    "the TCP router points at its own service" = sojuTcp.routers.soju.service == "soju";
    "a terminating TCP router uses the ACME resolver" = sojuTcp.routers.soju.tls.certResolver == "letsencrypt";
    "a terminating TCP router names its domain for the certificate" = sojuTcp.routers.soju.tls.domains == [{main = "irc.example.com";}];
    "the TCP service forwards to the backend" = sojuTcp.services.soju.loadBalancer.servers == [{address = "[::1]:6667";}];
    "the TCP service uses its own servers transport" = sojuTcp.services.soju.loadBalancer.serversTransport == "soju";
    "the servers transport sends PROXY protocol version 2" = sojuTcp.serversTransports.soju.proxyProtocol.version == 2;
    "the deprecated loadBalancer.proxyProtocol is not written" = !(sojuTcp.services.soju.loadBalancer ? proxyProtocol);
    "entryPoint.name names the entrypoint" = (entryPoints renamed).ircs.address == ":6697" && !((entryPoints renamed) ? soju);
    "the router follows a renamed entrypoint" = renamed.dynamicConfigOptions.tcp.routers.soju.entryPoints == ["ircs"];
    "proxyProtocol = null writes no serversTransport" = !(noProxy.dynamicConfigOptions.tcp.services.soju.loadBalancer ? serversTransport);
    "proxyProtocol = null writes no servers transports" = !(noProxy.dynamicConfigOptions.tcp ? serversTransports);
    "a passthrough router without ACME trips no traefik assertion" = !rejectedWith "othrys.services.traefik" passthroughCfg;
    "a passthrough router passes TLS through" = passthroughRouter.tls == {passthrough = true;};
    "a passthrough router names no resolver" = !(passthroughRouter.tls ? certResolver);
    "the firewall opens the TCP port beside 80 and 443 by default" = opens 6697 sojuCfg && opens 80 sojuCfg && opens 443 sojuCfg;
    "a router can open its port while the module keeps 80 and 443 closed" = opens 6697 routerOnly && !opens 80 routerOnly && !opens 443 routerOnly;
    "a router follows the module's openFirewall by default" = !opens 6697 routerDefaultClosed;
    "a router with openFirewall = false leaves its port closed" = !opens 6697 routerClosed && opens 80 routerClosed && opens 443 routerClosed;

    # tcpRouters refusals
    "a terminating router without ACME is refused" = rejectedWith "terminate TLS with the ACME resolver" terminatingNoAcme;
    "two routers on one port are refused" = rejectedWith "listens on port 6697" sharedPort;
    "two routers on one entrypoint name are refused" = rejectedWith "uses the entrypoint ircs" sharedName;
    "a router named for the module's own entrypoint is refused" = rejectedWith "which this module uses for its own entrypoint" reservedName;
    "a router on port 443 is refused" = rejectedWith "takes port 443" on443;
    "a router on 8080 beside the insecure dashboard is refused" = rejectedWith "takes port 8080" on8080Insecure;
    "a router on 8080 without the insecure dashboard is accepted" = !rejectedWith "takes port 8080" on8080Secure;
  }
