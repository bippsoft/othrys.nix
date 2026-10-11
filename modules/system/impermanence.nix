# modules/system/impermanence.nix
# Impermanence adapter, which hands the persistence registry to the impermanence module
#
# Exported as nixosModules.impermanence and left out of nixosModules.default,
# so a host imports it together with the impermanence module or imports
# neither. It is the only file in this tree that writes into the
# `environment.persistence` option namespace or orders a step against the
# activation scripts the impermanence module declares.
#
# The othrys.system.impermanence options and the root wipe live in
# ./ephemeral-root.nix, and the registry in ./persistence.nix. Both are part
# of nixosModules.default, so a module can name what it persists on a host
# that imports no impermanence module at all.
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.system.impermanence;
  inherit (cfg) persistRoot;
  persistenceEnabled = config.othrys.system.persistence.enable;

  # Every module's contribution, in the order of the registry keys.
  # attrValues returns them sorted by key, so the order is stable across
  # evaluations and does not follow the order modules are imported in.
  registry = config.othrys.internal.persist;
  collect = pick: lib.concatMap pick (lib.attrValues registry);
  userDirectories = collect (entry: entry.user.directories);
  userFiles = collect (entry: entry.user.files);
in {
  config = lib.mkMerge [
    {
      # What the assertion in ./ephemeral-root.nix reads. It is true on every
      # host that imports this file, whether or not impermanence is on.
      othrys.internal.impermanenceExport = true;

      # ANCHOR: persist-splice
      # Both guards are applied here, once, and at the attribute-set level.
      # With impermanence off the persist root is not declared at all. With
      # no managed account the `users` set stays empty, since the
      # impermanence module reads users.users.<name>.home for every entry
      # under it and that account does not exist. A guard on a leaf would
      # still declare the user and fail there.
      #
      # The root is declared once any module has a key in the registry, and
      # the user once any module names a path in the home. A host on which
      # no module persists anything therefore keeps an empty
      # environment.persistence.
      environment.persistence = lib.mkIf (cfg.enable && registry != {}) {
        ${persistRoot} = {
          # Part of the system-critical set, so it follows that switch.
          hideMounts = lib.mkIf persistenceEnabled true;

          directories = collect (entry: entry.directories);
          files = collect (entry: entry.files);

          users = lib.mkIf (usersEnabled && (userDirectories != [] || userFiles != [])) {
            ${username} = {
              directories = userDirectories;
              files = userFiles;
            };
          };
        };
      };
      # ANCHOR_END: persist-splice
    }

    (lib.mkIf (cfg.enable && persistenceEnabled) {
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
      #
      # The step is ordered between two activation scripts of the impermanence
      # module, which is why it lives in this file.
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
    })
  ];
}
