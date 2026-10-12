# modules/system/persistence.nix
# Persistence registry, with the system-critical and cross-cutting user entries
#
# Every module names what it keeps across the root wipe in
# othrys.internal.persist, declared below. nixosModules.impermanence
# (./impermanence.nix) reads the registry and is the one file that hands it
# to the impermanence module.
#
# ANCHOR: app-persistence-index
# App-specific persistence lives in each app's module:
# - Steam → modules/apps/gui/gaming/steam.nix
# - Floorp → modules/apps/gui/floorp/default.nix
# - Signal → modules/apps/gui/signal.nix
# - Plexamp → modules/apps/gui/plexamp.nix
# - Audio → modules/hardware/audio.nix
# - Printing → modules/services/printing.nix
# - Tailscale → modules/services/tailscale.nix
# - Zsh/Zoxide → modules/system/shell/zsh.nix
# - Direnv → modules/apps/cli/development.nix
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

  # ANCHOR: persist-registry
  # Every othrys module that keeps state across the root wipe writes here,
  # keyed by its own option path, and nixosModules.impermanence is the only
  # file that writes the option the impermanence module declares.
  #
  # That option exists only on a host that imports the impermanence module,
  # and a write into an option nothing declares fails whatever condition
  # guards it. A module that wrote there directly made every host import the
  # impermanence module, a host with a persistent root included. This option
  # is declared by othrys itself, so a write to it evaluates everywhere and
  # is read only where the export is imported and impermanence is on.
  #
  # The export also applies the two guards, once. System paths are bound when
  # impermanence is on, and the paths under `user` only when
  # othrys.system.users.enable is on as well, since the impermanence module
  # resolves them against the home of an account that has to exist. No module
  # spells either guard, so none can spell it wrongly.
  #
  # A module with a second condition wraps its own value in lib.mkIf. The key
  # then disappears when the condition is false. lib.mkIf on a single list
  # works as well.
  #
  # The value is a typed submodule, unlike othrys.internal.homeConfig, which
  # is raw. A home-manager contribution carries lib.mkForce and lib.mkDefault
  # that have to reach home-manager unprocessed. A persistence entry is a
  # plain path with an optional owner and mode and carries no priority, so
  # the lists are merged here. That lets two blocks of one module share a
  # key, lets lib.mkIf sit on one list, and reports a misspelt attribute at
  # the module that wrote it.
  #
  # An entry keeps the forms the impermanence module accepts. It is a string,
  # or an attribute set with `directory` or `file` and any of `user`, `group`
  # and `mode`. The export passes each entry on unchanged, and the
  # impermanence module checks the attribute names.
  options.othrys.internal.persist = let
    entries = description:
      lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything));
        default = [];
        inherit description;
      };
  in
    lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          directories = entries "System directories to keep, as absolute paths.";
          files = entries "System files to keep, as absolute paths.";
          user = {
            directories = entries "Directories to keep in the primary user's home, relative to it.";
            files = entries "Files to keep in the primary user's home, relative to it.";
          };
        };
      });
      default = {};
      internal = true;
      # The sub-options would otherwise be listed in the options reference
      # under a parent that is not.
      visible = false;
      example = lib.literalExpression ''{ "services.tailscale".directories = [ "/var/lib/tailscale" ]; }'';
      description = "Per-module persistent paths, keyed by option path, handed to the impermanence module by nixosModules.impermanence.";
    };
  # ANCHOR_END: persist-registry

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
