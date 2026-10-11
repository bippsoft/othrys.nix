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

    # /nix/var used to be in the persisted set. The nix subvolume survives the
    # wipe on its own, so the entry was redundant on every host, and on a
    # fresh install it hid the install-time database: the installer writes
    # /nix/var to the nix subvolume, the first boot bind-mounted an empty
    # persisted directory over it, and the first switch started from an empty
    # database. A host that has run through that first switch has its live
    # database under the persist root, and dropping the entry would put it
    # back onto the stale install-time copy at the next boot, with every
    # generation since lost.
    #
    # This step moves such a host onto the nix subvolume in one consistent
    # copy. Every Nix process holds a shared lock on big-lock while its store
    # is open, so the exclusive lock below waits for any open store to close
    # and blocks new ones for the duration. The copy is a reflink on btrfs.
    # On a running host, where the bind mount is still up, the subvolume's own
    # directory is reached through a private non-recursive bind of /nix, the
    # copy goes there, and the mount is dropped while the lock is still held,
    # so no write can land on the persisted copy after the copy was taken. If
    # the unmount is refused the mount stays, the interim copy is marked, and
    # the next boot, where nothing runs yet, finishes the move. Nothing is
    # deleted: the install-time copy is kept as var.install and the persisted
    # one as var.migrated, both for the operator to remove.
    #
    # Transitional. Remove once every host has passed through it, and before
    # v1.0.0.
    system.activationScripts.othrys-adopt-nix-var = {
      deps = [];
      text = ''
        persisted=${lib.escapeShellArg "${persistRoot}/nix/var"}
        live=/nix/var
        marker=.othrys-interim-copy
        findmnt=${pkgs.util-linux}/bin/findmnt
        flock=${pkgs.util-linux}/bin/flock
        mount=${pkgs.util-linux}/bin/mount
        umount=${pkgs.util-linux}/bin/umount
        cp=${pkgs.coreutils}/bin/cp
        mv=${pkgs.coreutils}/bin/mv
        rm=${pkgs.coreutils}/bin/rm
        mktemp=${pkgs.coreutils}/bin/mktemp
        rmdir=${pkgs.coreutils}/bin/rmdir
        systemctl=${config.systemd.package}/bin/systemctl

        # The first free name among $1.$2, $1.$2.1, $1.$2.2 and so on.
        free_name() {
          dest="$1.$2"
          n=1
          while [ -e "$dest" ]; do dest="$1.$2.$n"; n=$((n + 1)); done
          echo "$dest"
        }

        # Every entry of directory $1, dotfiles included.
        entries() {
          shopt -s nullglob dotglob
          printf '%s\n' "$1"/*
          shopt -u nullglob dotglob
        }

        # Move every entry of $1 into $2. The directories themselves stay
        # where they are: the subvolume's own /nix/var is the mount point of
        # the bind mount while that is up, and a directory that is a mount
        # point cannot be renamed.
        move_entries() {
          entries "$1" | while IFS= read -r e; do $mv "$e" "$2/" || return 1; done
        }

        # Copy directory $1 into a staging directory beside $2, then swap the
        # contents of $2 for the copy. Nothing in $2 changes unless the whole
        # copy succeeded. What $2 held before goes to $2.install, or is
        # removed when it is an interim copy this step made itself.
        replace_with_copy() {
          staging="$2.new"
          $rm -rf "$staging"
          if ! $cp -a --reflink=auto "$1" "$staging"; then
            $rm -rf "$staging"
            echo "othrys: copying $1 to $staging failed, nothing was changed" >&2
            return 1
          fi
          mkdir -p "$2"
          if [ -e "$2/$marker" ]; then
            entries "$2" | while IFS= read -r e; do $rm -rf "$e"; done
          elif [ -n "$(entries "$2")" ]; then
            aside=$(free_name "$2" install)
            mkdir "$aside" || return 1
            move_entries "$2" "$aside" || return 1
            echo "othrys: kept the previous contents of $2 as $aside"
          fi
          move_entries "$staging" "$2" || return 1
          $rmdir "$staging"
        }

        # Rename the persisted copy to its .migrated name.
        set_aside_persisted() {
          aside=$(free_name "$persisted" migrated)
          $mv "$persisted" "$aside" && echo "othrys: kept the persisted copy as $aside"
        }

        if [ -d "$persisted/nix/db" ]; then
          if $findmnt -n "$live" > /dev/null; then
            # The bind mount is up: a running host before its first reboot
            # on this configuration. The lock file is opened through the
            # persist root, which is the same inode and the same flock as
            # /nix/var/nix/db/big-lock, without holding anything under the
            # mount. A store that opens after the copy is blocked on this lock
            # with a descriptor under the mount, so the unmount below is
            # refused and the move defers, and nothing it writes is lost.
            exec 9>> "$persisted/nix/db/big-lock"
            if ! $flock -x -w 60 9; then
              echo "othrys: /nix/var is in use, the move onto the nix subvolume waits for the next switch or boot" >&2
            else
              view=$($mktemp -d /run/othrys-nix-view.XXXXXX)
              $mount --bind /nix "$view"
              if replace_with_copy "$live" "$view/var"; then
                if $umount "$live"; then
                  set_aside_persisted
                  echo "othrys: /nix/var moved onto the nix subvolume"
                  # The listening socket was bound to an inode under the old
                  # mount. Re-bind it at the path now that the path is the
                  # subvolume's copy.
                  if $systemctl is-active --quiet nix-daemon.socket; then
                    $systemctl stop nix-daemon.service nix-daemon.socket
                    $systemctl start nix-daemon.socket
                  fi
                else
                  : > "$view/var/$marker"
                  echo "othrys: /nix/var is busy, the move onto the nix subvolume finishes at the next boot" >&2
                fi
              fi
              $umount "$view"
              $rmdir "$view"
            fi
            exec 9>&-
          else
            # No mount: a boot on this configuration while the persisted copy
            # still exists, which is the boot after a refused unmount. The
            # persisted copy took every write of the previous boot, so it is
            # the live one, and nothing runs yet that could write either.
            if replace_with_copy "$persisted" "$live"; then
              set_aside_persisted
              echo "othrys: /nix/var moved onto the nix subvolume at boot"
            fi
          fi
        fi
      '';
    };

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
