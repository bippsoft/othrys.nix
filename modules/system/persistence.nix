# modules/system/persistence.nix
# ANCHOR: app-persistence-index
# App-specific persistence lives in each app's module:
# - Steam → modules/apps/gui/gaming/steam.nix
# - Floorp → modules/apps/gui/floorp/default.nix
# - Signal → modules/apps/gui/signal.nix
# - Plexamp → modules/apps/gui/plexamp.nix
# - Audio → modules/hardware/audio.nix
# - Printing → modules/services/printing.nix
# - Tailscale → modules/services/tailscale.nix
# - Zsh/Zoxide/Direnv → modules/system/shell/zsh.nix
# - Bluetooth → modules/hardware/wireless/bluetooth.nix
# - WiFi → modules/hardware/wireless/wifi.nix
# - GPG/YubiKey → modules/services/security/yubikey.nix
# ANCHOR_END: app-persistence-index
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.system.persistence;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # Standard XDG user dirs, mapping folder name to xdg.userDirs option name.
  # Both the persistence list and xdg.userDirs are derived from this.
  xdgUserDirs = {
    Desktop = "desktop";
    Documents = "documents";
    Downloads = "download";
    Music = "music";
    Pictures = "pictures";
    Videos = "videos";
    Public = "publicShare";
    Templates = "templates";
  };
in {
  options.othrys.system.persistence = {
    enable = lib.mkEnableOption "System-critical persistence declarations";
  };

  config = lib.mkIf (cfg.enable && impermanenceEnabled) {
    # The host keys live on the persist volume directly, at the path sops-nix
    # already reads them from (see ./secrets.nix). Persisting /etc/ssh as a
    # directory instead would mount over the /etc/ssh/sshd_config that
    # activation writes, and sshd on a freshly installed host would not start
    # until the first switch. Only read when services.openssh is enabled.
    services.openssh.hostKeys = [
      {
        path = "${persistRoot}/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "${persistRoot}/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];

    # ANCHOR: system-persistence
    environment.persistence.${persistRoot} = {
      hideMounts = true;

      directories = [
        {
          directory = "/var/lib/systemd";
          user = "root";
          group = "root";
          mode = "0755";
        }
        {
          directory = "/var/lib/nixos";
          user = "root";
          group = "root";
          mode = "0755";
        }
        {
          directory = "/nix/var";
          user = "root";
          group = "root";
          mode = "0755";
        }
        {
          directory = "/var/log";
          user = "root";
          group = "root";
          mode = "0755";
        }
        {
          directory = "/var/db/sudo/lectured";
          user = "root";
          group = "root";
          mode = "0700";
        }
      ];

      # /etc/machine-id keys the journal directory, the systemd-networkd DHCP
      # identity and anything else that tracks the host by id. Left on the
      # wiped root it is regenerated on every boot.
      files = [
        "/etc/adjtime"
        "/etc/machine-id"
      ];

      # ANCHOR_END: system-persistence

      # ANCHOR: user-persistence
      # Per-user persistence only when othrys manages the user account.
      # Headless hosts persist system state without a primary user.
      users = lib.mkIf usersEnabled {
        ${username} = {
          directories =
            (lib.attrNames xdgUserDirs)
            ++ [
              "Projects"
              {
                directory = ".ssh";
                mode = "0700";
              }
              ".cache/nix"
              ".local/state/home-manager"
              ".local/share/applications"
            ];

          files = [
            ".bash_history"
          ];
        };
      };
      # ANCHOR_END: user-persistence
    };

    othrys.internal.homeConfig."system.persistence".xdg.userDirs =
      {
        enable = true;
        createDirectories = true;
        setSessionVariables = true;
      }
      // lib.mapAttrs'
      (folder: opt: lib.nameValuePair opt "/home/${username}/${folder}")
      xdgUserDirs;
  };
}
