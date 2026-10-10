# flake/checks/grafana-eval.nix
# CORE. What the grafana module serves and refuses, read back from evaluated
# hosts. A host with no admin password file served the stock admin/admin
# credential on whatever address it listened on, with sign-up open and the
# session cookie unmarked, and none of that fails evaluation.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
}: let
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.services.grafana = {
          enable = true;
          secretKeyFile = "/run/secrets/grafana/secret-key";
        };
      }
      extra
    ];

  loopback = host {};
  exposed = host {
    othrys.services.grafana = {
      listenAddress = "0.0.0.0";
      rootUrl = "https://grafana.example.com/";
      adminPasswordFile = "/run/secrets/grafana/admin-password";
    };
  };
  exposedNoPassword = host {
    othrys.services.grafana = {
      listenAddress = "0.0.0.0";
      rootUrl = "https://grafana.example.com/";
    };
  };
  exposedNoRootUrl = host {
    othrys.services.grafana = {
      listenAddress = "0.0.0.0";
      adminPasswordFile = "/run/secrets/grafana/admin-password";
    };
  };
  openOnLoopback = host {othrys.services.grafana.openFirewall = true;};

  settings = cfg: cfg.services.grafana.settings;
  warnsAbout = needle: cfg: builtins.any (w: builtins.match ".*${needle}.*" w != null) cfg.warnings;
in
  mkExpectations "othrys-eval-grafana" {
    "sign-up is closed by default" = !(settings loopback).users.allow_sign_up;
    "the session cookie is not marked secure on loopback" = !(settings loopback).security.cookie_secure;
    "loopback keeps the upstream root_url" = (settings loopback).server.root_url == "%(protocol)s://%(domain)s:%(http_port)s/";
    "loopback without a password file warns about admin/admin" = warnsAbout "admin/admin" loopback;
    "loopback without a password file is accepted" = !rejectedWith "adminPasswordFile" loopback;
    "an exposed host writes its public URL" = (settings exposed).server.root_url == "https://grafana.example.com/";
    "an exposed https host marks the session cookie secure" = (settings exposed).security.cookie_secure;
    "an exposed host with a password file does not warn" = !warnsAbout "admin/admin" exposed;
    "an exposed host without a password file is refused" = rejectedWith "set adminPasswordFile" exposedNoPassword;
    "an exposed host without a root URL is refused" = rejectedWith "set rootUrl" exposedNoRootUrl;
    "an open port on loopback without a password file is refused" = rejectedWith "set adminPasswordFile" openOnLoopback;
  }
