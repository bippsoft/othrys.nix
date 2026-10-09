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
