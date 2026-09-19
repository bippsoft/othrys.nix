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
  pkgs,
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

    # impermanence bind-mounts the persisted /etc/machine-id, and its mount
    # script refuses a mount point that is already a regular, non-empty file.
    # At boot the root is fresh and the file is absent, so that never triggers.
    # On a host that was running before /etc/machine-id joined the persisted
    # set, the file holds this boot's id, and the first switch failed with "A
    # file already exists at /etc/machine-id!". This step runs first and turns
    # that state into the one the mount script accepts. The running id is the
    # one kept, so the journal and the DHCP identity of this boot carry on. A
    # persisted file that is missing, empty or a symlink is replaced, and one
    # that holds a different id is kept beside it. At boot it does nothing.
    system.activationScripts.othrys-persist-machine-id = {
      deps = ["createPersistentStorageDirs"];
      text = ''
        machine_id=/etc/machine-id
        persisted=${lib.escapeShellArg "${persistRoot}/etc/machine-id"}
        if [ -f "$machine_id" ] && [ ! -L "$machine_id" ] && [ -s "$machine_id" ] \
          && ! ${pkgs.util-linux}/bin/findmnt "$machine_id" > /dev/null \
          && [ "$(${pkgs.coreutils}/bin/cat "$machine_id")" != uninitialized ]; then
          if [ -f "$persisted" ] && [ ! -L "$persisted" ] && [ -s "$persisted" ] \
            && ! ${pkgs.diffutils}/bin/cmp -s "$machine_id" "$persisted"; then
            ${pkgs.coreutils}/bin/mv "$persisted" "$persisted.replaced"
          fi
          ${pkgs.coreutils}/bin/rm -f "$persisted"
          ${pkgs.coreutils}/bin/install -D -m 0444 "$machine_id" "$persisted"
          ${pkgs.util-linux}/bin/mount --bind "$persisted" "$machine_id"
          echo "persisted the running machine-id to $persisted"
        fi
      '';
    };
    system.activationScripts.persist-files.deps = ["othrys-persist-machine-id"];

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
