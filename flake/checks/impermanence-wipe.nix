# flake/checks/impermanence-wipe.nix
# EXTENDED. Boots the wipe unit itself. ./impermanence.nix runs the generated
# script from stage 2 against a spare disk, which proves the algorithm and
# nothing about the unit: whether the initrd renders it, whether its device
# dependency resolves, and whether every command it calls exists on the
# stage-1 PATH. This VM has a btrfs root on a disk it formats at first boot,
# so the unit runs for real on every boot, before sysroot.mount, with the
# PATH a host's initrd has. It writes a file in /, reboots, and asserts the
# file is gone and archived, then ages the archive past the retention window
# and asserts the next boot prunes it.
{
  pkgs,
  inputs,
}:
pkgs.testers.runNixOSTest {
  name = "othrys-impermanence-wipe";
  node.specialArgs = {inherit inputs;};

  nodes.machine = {lib, ...}: {
    imports = [
      inputs.self.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      inputs.sops-nix.nixosModules.sops
      {
        options.stylix = lib.mkOption {
          type = lib.types.attrs;
          default = {};
        };
      }
    ];

    # No root image: the first empty disk is /dev/vda and becomes the btrfs
    # root, the second is /dev/vdb and holds /persist. The root is formatted
    # by systemd-makefs in the initrd on the first boot, and the wipe unit
    # creates the `root` subvolume the mount then needs.
    virtualisation.diskImage = null;
    virtualisation.emptyDiskImages = [1024 256];
    virtualisation.useDefaultFilesystems = false;
    virtualisation.fileSystems = {
      "/" = {
        device = "/dev/vda";
        fsType = "btrfs";
        options = ["subvol=root"];
        autoFormat = true;
      };
      "/persist" = {
        device = "/dev/vdb";
        fsType = "ext4";
        autoFormat = true;
        neededForBoot = true;
      };
    };
    # The format of /dev/vda and the wipe are both ordered before
    # sysroot.mount and nothing else orders them against each other.
    boot.initrd.systemd.services.root-wipe.after = ["systemd-makefs@dev-vda.service"];

    # impermanence asserts on the disko layout. enableConfig = false keeps
    # disko from emitting the LUKS and filesystem config a VM cannot satisfy.
    disko.enableConfig = false;
    othrys.system = {
      disko = {
        enable = true;
        device = "/dev/vdc";
      };
      impermanence = {
        enable = true;
        device = "/dev/vda";
        retentionDays = 30;
      };
      persistence.enable = true;
    };

    environment.systemPackages = [pkgs.btrfs-progs];
  };

  testScript = ''
    def archive():
        # The top-level subvolume, where old_roots lives beside root.
        machine.succeed("mkdir -p /mnt/top && mount -o subvolid=5 /dev/vda /mnt/top")
        entries = machine.succeed("ls -1 /mnt/top/old_roots 2>/dev/null || true").split()
        machine.succeed("umount /mnt/top")
        return entries

    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("the first boot ran the unit in the initrd"):
        machine.succeed("journalctl -b -u root-wipe.service --no-pager | grep -q 'Finished'")
        assert archive() == [], f"a fresh disk has no archive, got {archive()!r}"
        machine.succeed("touch /canary")
        machine.succeed("echo durable > /persist/keepme")

    with subtest("the root is wiped and archived on the next boot"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.fail("test -e /canary")
        machine.succeed("grep -q durable /persist/keepme")
        entries = archive()
        assert len(entries) == 1, f"expected one archived root, got {entries!r}"
        machine.succeed("mount -o subvolid=5 /dev/vda /mnt/top")
        machine.succeed(f"test -e /mnt/top/old_roots/{entries[0]}/canary")
        machine.succeed("umount /mnt/top")

    with subtest("an archived root past the retention window is pruned at boot"):
        machine.succeed("mount -o subvolid=5 /dev/vda /mnt/top")
        machine.succeed(f"touch -d '90 days ago' /mnt/top/old_roots/{entries[0]}")
        # A stray directory that is not a subvolume must survive a prune.
        machine.succeed("mkdir /mnt/top/old_roots/stray && touch -d '90 days ago' /mnt/top/old_roots/stray")
        machine.succeed("umount /mnt/top")
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        after = archive()
        assert entries[0] not in after, f"aged root {entries[0]} was not pruned: {after!r}"
        assert "stray" in after, f"the stray directory was deleted: {after!r}"
        assert len(after) == 2, f"expected the stray entry and the new archive, got {after!r}"
        machine.succeed("journalctl -b -u root-wipe.service --no-pager | grep -q 'skipping non-subvolume'")

    with subtest("no unit failed across the three boots"):
        failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
        assert failed == "", f"failed units: {failed}"
  '';
}
