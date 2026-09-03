# modules/services/docs.nix
# MdBook documentation server, building and serving docs from the flake source
{
  config,
  lib,
  pkgs,
  # Source of the othrys flake, injected by nixosModules.default (flake/modules.nix).
  # Null when this file is imported standalone, in which case cfg.package must be set.
  othrysSelf ? null,
  ...
}: let
  cfg = config.othrys.services.docs;

  docsPackage =
    if othrysSelf == null
    then throw "othrys.services.docs: no flake source available; set othrys.services.docs.package explicitly"
    else
      pkgs.stdenv.mkDerivation {
        pname = "othrys-docs";
        # Derived from the flake source rather than written out, so it cannot
        # disagree with what was actually built. A dirty or path-copied source
        # has no revision, hence the fallback.
        version = othrysSelf.shortRev or othrysSelf.dirtyShortRev or "dev";
        src = othrysSelf;
        nativeBuildInputs = [pkgs.mdbook];
        buildPhase = "mdbook build docs/";
        installPhase = "cp -r docs/book $out";
      };

  docsUrl = "http://${cfg.interface}:${toString cfg.port}";
in {
  # ANCHOR: docs-options
  options.othrys.services.docs = {
    enable = lib.mkEnableOption "MdBook documentation server";

    package = lib.mkOption {
      type = lib.types.package;
      default = docsPackage;
      defaultText = lib.literalExpression "built MdBook from docs/";
      description = "The built documentation package to serve.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port to serve documentation on.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Interface to bind to (use 0.0.0.0 for all interfaces).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port for documentation server.";
    };

    desktopEntry = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Create a desktop entry to open docs in the default browser.";
    };
  };
  # ANCHOR_END: docs-options

  config = lib.mkIf cfg.enable {
    systemd.services.othrys-docs = {
      description = "othrys.nix documentation server.";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.darkhttpd}/bin/darkhttpd ${cfg.package} --port ${toString cfg.port} --addr ${cfg.interface}";
        Restart = "on-failure";
        RestartSec = "5s";

        # Hardening
        DynamicUser = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    # Desktop entry only when this host wants one. The homeManaged guard is
    # applied once by othrys.system.users, so the condition here is the module's
    # own. A false condition drops the key, so nothing is written and nothing is
    # reported as skipped.
    othrys.internal.homeConfig."services.docs" = lib.mkIf cfg.desktopEntry {
      xdg.desktopEntries.othrys-docs = {
        name = "othrys.nix Docs";
        comment = "Open NixOS configuration documentation";
        exec = "${pkgs.xdg-utils}/bin/xdg-open ${docsUrl}";
        icon = "accessories-dictionary";
        terminal = false;
        categories = ["Documentation"];
      };
    };
  };
}
