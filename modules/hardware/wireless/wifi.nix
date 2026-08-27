# modules/hardware/wireless/wifi.nix
# NetworkManager for WiFi and mobile broadband with declarative network support
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.hardware.wireless.wifi;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  networkingCfg = config.othrys.system.networking;

  # Generate NetworkManager profile for a WiFi network
  mkWifiProfile = name: network: {
    connection = {
      id = network.ssid;
      type = "wifi";
      inherit (network) autoconnect;
    };
    wifi = {
      inherit (network) ssid;
      mode = "infrastructure";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      # Use environment variable substitution for password
      psk = "$WIFI_PSK_${lib.toUpper (builtins.replaceStrings ["-" " "] ["_" "_"] name)}";
    };
    ipv4.method = "auto";
    ipv6.method = "auto";
  };
in {
  options.othrys.hardware.wireless.wifi = {
    enable = lib.mkEnableOption "NetworkManager WiFi networking";

    networks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          ssid = lib.mkOption {
            type = lib.types.str;
            description = "WiFi network SSID.";
          };

          autoconnect = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Automatically connect to this network.";
          };
        };
      });
      default = {};
      example = lib.literalExpression ''
        {
          home = { ssid = "MyHomeNetwork"; };
          work = { ssid = "WorkNetwork"; autoconnect = false; };
        }
      '';
      description = "Declarative WiFi networks (passwords via environmentFile).";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "config.sops.secrets.\"networking/wifi/env\".path";
      description = ''
        Path to environment file containing WiFi passwords.
        Format: WIFI_PSK_<NETWORK_NAME>=password
        Example: WIFI_PSK_HOME=mysecretpassword
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for NetworkManager state (manual connections, leases, etc.)
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/etc/NetworkManager";
          user = "root";
          group = "root";
          mode = "0755";
        }
        {
          directory = "/etc/NetworkManager/system-connections";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];
    };

    networking.networkmanager = {
      enable = true;
      wifi.powersave = true;

      # When systemd-networkd manages wired interfaces, tell NM to leave them alone
      unmanaged = lib.mkIf networkingCfg.enable (
        lib.mapAttrsToList (_: iface: "interface-name:${iface.match}") networkingCfg.interfaces
      );

      # Declarative network profiles
      ensureProfiles = lib.mkIf (cfg.networks != {}) {
        profiles = lib.mapAttrs mkWifiProfile cfg.networks;
        environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
      };
    };

    # Add user to networkmanager group, only when othrys manages the user
    # account (writing users.users.<name> otherwise materializes a phantom user).
    users.users = lib.mkIf usersEnabled {
      ${username}.extraGroups = ["networkmanager"];
    };

    # NetworkManager tray applet only on desktop hosts. Headless WiFi boxes
    # (routers, APs) use nmcli/nmtui and skip the GTK closure.
    environment.systemPackages = lib.optionals config.othrys.desktop.graphical (with pkgs; [
      networkmanagerapplet
    ]);
  };
}
