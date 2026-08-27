# modules/services/security/crowdsec.nix
# CrowdSec security engine + nftables firewall bouncer (both in nixpkgs). The
# engine parses logs and decides, while the bouncer enforces those decisions in
# nftables. registerBouncer wires the two automatically, so no manual
# `cscli bouncers add` / API key is needed for the local setup.
#
# Central-console enrollment (crowd-sourced blocklists) is a one-time runtime
# step, `cscli console enroll <key>` with a key from your secrets provider,
# and is intentionally left to the fleet.
#
# As shipped, nixpkgs' `services.crowdsec` cannot start on a host that has no
# pre-existing /var/lib/crowdsec. Four independent upstream defects each abort
# one of the three units (no local API, no cscli config, a
# DynamicUser/StateDirectory cascade, an unordered bouncer dependency), and a
# fifth fails the daily hub-update timer a day later. Every workaround below
# sits at the config block that repairs it and names its upstream issue, and the
# `crowdsec-test` check in flake/checks/crowdsec.nix boots a fresh VM and is the
# regression guard, so drop a workaround only when that test still passes.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.services.security.crowdsec;

  stateDir = "/var/lib/crowdsec/state";

  # The very file nixpkgs generates for the daemon's `crowdsec -c …` (same
  # name and value, so the same store path), regenerated here because
  # the module keeps it private. See the cscli workaround below.
  configFile = (pkgs.formats.yaml {}).generate "crowdsec.yaml" config.services.crowdsec.settings.general;
in {
  # ANCHOR: crowdsec-options
  options.othrys.services.security.crowdsec = {
    enable = lib.mkEnableOption "CrowdSec security engine + firewall bouncer";

    collections = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["crowdsecurity/linux" "crowdsecurity/sshd"];
      description = "CrowdSec hub collections to install (bundle parsers + scenarios).";
    };

    acquisitions = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [
        {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
          labels.type = "syslog";
        }
      ];
      description = ''
        Log sources CrowdSec parses (see the CrowdSec data-sources docs).
        Setting this replaces the curated default outright, including the sshd
        journal source, so list every source the host should watch rather than
        only the ones being added.
      '';
    };

    autoUpdate = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run `cscli hub update` daily.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the CrowdSec LAPI port in the firewall.";
    };

    firewallBouncer.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the nftables firewall bouncer that enforces CrowdSec decisions (auto-registered with the local engine).";
    };
  };
  # ANCHOR_END: crowdsec-options

  config = lib.mkIf cfg.enable {
    services.crowdsec = {
      enable = true;
      autoUpdateService = cfg.autoUpdate;
      inherit (cfg) openFirewall;
      hub.collections = cfg.collections;
      localConfig.acquisitions = cfg.acquisitions;

      # A single-host engine is its own Local API, so the agent authenticates to
      # it with machine credentials, and the bouncer reads decisions from it
      # over loopback. nixpkgs leaves the LAPI off AND the credentials path
      # null, so the daemon dies at startup with
      #   loading api client: no API client section in configuration
      # i.e. `services.crowdsec.enable = true` alone never boots (nixpkgs
      # #445342). Credentials are minted on first start by the module's own
      # `cscli machine add --auto` step, which only runs when the LAPI is on.
      settings = {
        general.api.server.enable = true;
        lapi.credentialsFile = "${stateDir}/local_api_credentials.yaml";
      };
    };

    services.crowdsec-firewall-bouncer = lib.mkIf cfg.firewallBouncer.enable {
      enable = true;
      # Register with the locally running engine (no manual API key needed).
      registerBouncer.enable = true;
    };

    # `cscli` defaults to /etc/crowdsec/config.yaml, but nixpkgs only ever
    # passes `-c <store path>`, and nothing populates that path, so every cscli
    # call that is not the module's own wrapper fails with
    #   while reading yaml file: open /etc/crowdsec/config.yaml: no such file
    # That includes the bouncer's register unit, which invokes the raw binary
    # (nixpkgs #469519, with a revert pending in #500515). Link the daemon's own
    # config into place, and the tmpfiles ordering prefix keeps this after the
    # module's own 10-crowdsec rules, which create the directory.
    systemd.tmpfiles.settings."20-crowdsec-cscli"."/etc/crowdsec/config.yaml".link = {
      type = "L+";
      argument = "${configFile}";
    };

    systemd.services = let
      # nixpkgs runs the engine under DynamicUser=true even though the module
      # declares a static `crowdsec` account and chowns /etc/crowdsec and
      # /var/lib/crowdsec to it. systemd honours DynamicUser over User=, so the
      # units run as a transient UID that owns none of that, and the register
      # unit, the only one declaring StateDirectory=, migrates
      # /var/lib/crowdsec into /var/lib/private (0700 root). From the next boot
      # on, the engine (no StateDirectory=) cannot even create its hub dir:
      #   mkdir: cannot create directory '/var/lib/crowdsec': Permission denied
      # Pinning the units to the declared account makes on-disk ownership
      # coherent again, and systemd migrates the state dir back out of
      # /var/lib/private on the next start (nixpkgs #520206).
      staticUser = {
        DynamicUser = lib.mkForce false;
        StateDirectory = "crowdsec";
      };
    in {
      crowdsec.serviceConfig =
        staticUser
        // {
          # nixpkgs clears the packaged unit's ExecReload without providing
          # one, so the engine cannot be reloaded at all, which is what the
          # hub-update unit below tries to do every day (nixpkgs #541058).
          # CrowdSec reloads on SIGHUP, as its own packaged unit does.
          ExecReload = lib.mkForce [
            " " # clear the definitions inherited from the upstream unit
            "${pkgs.coreutils}/bin/kill -HUP $MAINPID"
          ];
        };

      crowdsec-update-hub = lib.mkIf cfg.autoUpdate {
        serviceConfig =
          staticUser
          // {
            # `cscli hub update` succeeds and then the unit dies in
            # ExecStartPost reloads crowdsec.service as the unprivileged
            # crowdsec user, which systemd refuses (Access denied,
            # status=4/NOPERMISSION), so the daily timer leaves a failed unit
            # on every host (nixpkgs #473707). `+` runs that one command with
            # full privileges, which is what it needs.
            ExecStartPost = lib.mkForce "+systemctl reload crowdsec.service";
          };
      };

      crowdsec-firewall-bouncer-register = lib.mkIf cfg.firewallBouncer.enable {
        # StateDirectory= is already correct here (it also owns the api-key
        # credential), and only the identity needs fixing. DynamicUser= implied a
        # few hardening knobs, so restate them rather than lose them.
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          ProtectSystem = "strict";
          PrivateTmp = true;
          RemoveIPC = true;
          NoNewPrivileges = true;
          RestrictSUIDSGID = true;
        };
      };

      # nixpkgs gives the bouncer Requires= on the register unit but no
      # ordering, so on a fresh host the two race and the bouncer loses, since its
      # LoadCredential= names the API key the register unit has not written
      # yet, and it dies at step CREDENTIALS with no retry (the symptom
      # reported in nixpkgs #526506). The After=nftables.service ordering this
      # module used to add (nixpkgs #476253) is upstream now, so it is gone.
      crowdsec-firewall-bouncer = lib.mkIf cfg.firewallBouncer.enable {
        after = ["crowdsec-firewall-bouncer-register.service"];
      };
    };
  };
}
