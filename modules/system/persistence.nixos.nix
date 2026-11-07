# modules/system/persistence.nixos.nix
# The system-critical and cross-cutting user entries of the persistence registry
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
  imports = [./persistence.nix];

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

    # /nix/var is not in the persisted set. The nix subvolume survives the
    # wipe on its own, so the database, the profiles and the GC roots stay
    # where the installer put them.

    # ANCHOR: system-persistence
    othrys.internal.persist."system.persistence" = {
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
      # Bound only on a host where othrys manages the user account. A
      # headless host persists system state without a primary user.
      user = {
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
      # ANCHOR_END: user-persistence
    };

    # The directories sit under the home the account declares, which a host
    # may place outside /home. The persistence entries above are relative, so
    # impermanence already resolves them against the same value. Reading the
    # account needs it to exist, so the entry is dropped on a host where
    # othrys creates no account.
    othrys.internal.homeConfig."system.persistence" = lib.mkIf usersEnabled {
      xdg.userDirs =
        {
          enable = true;
          createDirectories = true;
          setSessionVariables = true;
        }
        // lib.mapAttrs'
        (folder: opt: lib.nameValuePair opt "${config.users.users.${username}.home}/${folder}")
        xdgUserDirs;
    };
  };
}
