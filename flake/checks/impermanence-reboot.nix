# flake/checks/impermanence-reboot.nix
# EXTENDED. Host-identity proof for the persistence set. ./impermanence.nix
# runs the wipe script against a btrfs image and cannot say whether what
# othrys persists is enough for a host to stay the same host. This boots a VM
# whose root is a tmpfs, so every boot starts from an empty root exactly as
# the wipe leaves it, with /persist on a disk that survives. It records the
# machine-id, the SSH host key and the journal directory, reboots, and
# compares all three. It then puts the running VM into the state of a host
# that predates the persisted machine-id and runs the activation, which is the
# first live switch such a host makes.
{
  pkgs,
  inputs,
}:
pkgs.testers.runNixOSTest {
  name = "othrys-impermanence-reboot";
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

    # A null disk image makes the root a tmpfs, which is the wipe's effect
    # without the LUKS and btrfs layout the wipe script itself needs.
    virtualisation.diskImage = null;
    virtualisation.emptyDiskImages = [512];
    virtualisation.fileSystems."/persist" = {
      device = "/dev/vda";
      fsType = "ext4";
      autoFormat = true;
      neededForBoot = true;
    };

    # impermanence asserts on the disko layout. enableConfig = false keeps
    # disko from emitting the LUKS and filesystem config a VM cannot satisfy,
    # and the wipe unit is switched off because it waits for that LUKS device.
    # The tmpfs root stands in for it.
    disko.enableConfig = false;
    boot.initrd.systemd.services.root-wipe.enable = lib.mkForce false;
    othrys.system = {
      disko = {
        enable = true;
        device = "/dev/vdb";
      };
      impermanence.enable = true;
      persistence.enable = true;
    };

    othrys.services.ssh = {
      enable = true;
      server.enable = true;
    };
  };

  testScript = ''
    def identity():
        machine_id = machine.succeed("cat /etc/machine-id").strip()
        host_key = machine.succeed(
            "ssh-keygen -lf /persist/etc/ssh/ssh_host_ed25519_key.pub"
        ).split()[1]
        journals = machine.succeed("ls -1 /var/log/journal").split()
        return machine_id, host_key, journals

    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sshd.service")

    with subtest("the first boot settles on one identity"):
        first_id, first_key, first_journals = identity()
        assert len(first_id) == 32, f"machine-id is not initialised: {first_id!r}"
        assert first_journals == [first_id], f"journal dirs {first_journals} do not match {first_id}"
        machine.succeed("touch /etc/canary /root/canary")

    with subtest("the root does not survive a reboot"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("sshd.service")
        machine.fail("test -e /etc/canary")
        machine.fail("test -e /root/canary")

    with subtest("the host identity does"):
        second_id, second_key, second_journals = identity()
        assert second_id == first_id, f"machine-id changed: {first_id} -> {second_id}"
        assert second_key == first_key, f"SSH host key changed: {first_key} -> {second_key}"
        assert second_journals == [first_id], f"journal dirs after reboot: {second_journals}"
        boots = machine.succeed("journalctl --list-boots --no-pager | grep -c .").strip()
        assert int(boots) >= 2, f"journal holds {boots} boot(s), expected both"

    with subtest("no unit fails over the persisted machine-id"):
        failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
        assert failed == "", f"failed units: {failed}"

    with subtest("a host that ran before the id was persisted migrates on its first switch"):
        # The state such a host is in: /etc/machine-id is a plain file holding
        # this boot's id, nothing is mounted over it, and the persist root
        # holds a dangling symlink left by an older configuration.
        machine.succeed("cat /etc/machine-id > /tmp/running-id")
        machine.succeed("umount /etc/machine-id")
        machine.succeed("cat /tmp/running-id > /etc/machine-id")
        machine.succeed("rm /persist/etc/machine-id")
        machine.succeed("ln -s /etc/static/machine-id /persist/etc/machine-id")
        machine.fail("findmnt /etc/machine-id")

        machine.succeed("/run/current-system/activate")
        machine.succeed("systemctl restart 'persist-persist-etc-machine\\x2did.service'")

        machine.succeed("findmnt /etc/machine-id")
        machine.succeed("test -f /persist/etc/machine-id -a ! -L /persist/etc/machine-id")
        assert machine.succeed("cat /etc/machine-id").strip() == first_id, "the running id changed"
        assert machine.succeed("cat /persist/etc/machine-id").strip() == first_id, "the persisted id is not the running one"
        failed = machine.succeed("systemctl --failed --no-legend --plain").strip()
        assert failed == "", f"failed units: {failed}"

    with subtest("the migrated id survives the next reboot"):
        machine.shutdown()
        machine.start()
        machine.wait_for_unit("multi-user.target")
        third_id, third_key, third_journals = identity()
        assert third_id == first_id, f"machine-id changed after the migration: {first_id} -> {third_id}"
        assert third_key == first_key, "SSH host key changed after the migration"
        assert third_journals == [first_id], f"journal dirs after the migration: {third_journals}"

    with subtest("a persisted file holding another id is kept beside the running one"):
        machine.succeed("umount /etc/machine-id")
        machine.succeed(f"echo {first_id} > /etc/machine-id")
        machine.succeed("echo 0123456789abcdef0123456789abcdef > /persist/etc/machine-id")
        machine.succeed("/run/current-system/activate")
        assert machine.succeed("cat /persist/etc/machine-id").strip() == first_id
        assert machine.succeed("cat /persist/etc/machine-id.replaced").strip() == "0123456789abcdef0123456789abcdef"

    # /nix/var used to be in the persisted set. A host that ran under that
    # configuration has its live database under the persist root, bind-mounted
    # over the nix subvolume's own copy, which still holds the install-time
    # state. The state is staged here the same way: the subvolume copy is
    # marked, the live copy is put under the persist root and mounted over it.
    def db_sum():
        return machine.succeed("sha256sum /nix/var/nix/db/db.sqlite").split()[0]

    with subtest("a host with /nix/var still persisted moves onto the nix subvolume at its first switch"):
        machine.succeed("echo install-time > /nix/var/.origin")
        machine.succeed("mkdir -p /persist/nix && cp -a /nix/var /persist/nix/var && rm /persist/nix/var/.origin")
        machine.succeed("mount --bind /persist/nix/var /nix/var")
        machine.succeed("echo live > /nix/var/.live")
        before = db_sum()
        generations = machine.succeed("ls -1 /nix/var/nix/profiles").split()
        machine.succeed("/run/current-system/activate")
        machine.fail("findmnt /nix/var")
        machine.succeed("test -e /nix/var/.live")
        machine.fail("test -e /nix/var/.origin")
        machine.succeed("test -e /nix/var.install/.origin")
        machine.fail("test -e /persist/nix/var")
        machine.succeed("test -e /persist/nix/var.migrated/.live")
        assert db_sum() == before, "the database changed during the move"
        assert machine.succeed("ls -1 /nix/var/nix/profiles").split() == generations, "a profile went missing"
        machine.succeed("nix-store --verify")
        machine.succeed("nix-store --store daemon -q --hash /run/current-system")

    with subtest("a refused unmount keeps the mount and the move finishes at the next boot"):
        machine.succeed("cp -a /nix/var /persist/nix/var")
        machine.succeed("mount --bind /persist/nix/var /nix/var")
        machine.succeed("echo busy > /nix/var/.busy")
        # systemd-run resolves a bare command through systemd's own PATH,
        # which has no NixOS entries, so both programs are named in full.
        machine.succeed(
            "systemd-run --unit=holder /bin/sh -c 'exec ${pkgs.coreutils}/bin/sleep infinity < /nix/var/.busy'"
        )
        machine.wait_until_succeeds(
            "ls -l /proc/$(systemctl show -p MainPID --value holder)/fd | grep -q /nix/var/.busy"
        )
        machine.succeed("/run/current-system/activate")
        machine.succeed("findmnt /nix/var")
        machine.succeed("test -d /persist/nix/var")
        # A write after the refused unmount lands on the persisted copy, which
        # is still the live one, and must survive the move.
        machine.succeed("echo late > /nix/var/.late")
        machine.succeed("systemctl stop holder")
        # The next boot has no mount and the persisted copy still there.
        machine.succeed("umount /nix/var")
        machine.fail("test -e /nix/var/.late")
        machine.succeed("test -e /nix/var/.othrys-interim-copy")
        machine.succeed("/run/current-system/activate")
        machine.fail("findmnt /nix/var")
        machine.succeed("test -e /nix/var/.late")
        machine.fail("test -e /nix/var/.othrys-interim-copy")
        machine.fail("test -e /persist/nix/var")
        machine.succeed("test -e /persist/nix/var.migrated.1/.late")
        machine.succeed("nix-store --verify")

    with subtest("a host that never had the mount is left alone"):
        machine.succeed("/run/current-system/activate")
        machine.fail("findmnt /nix/var")
        machine.succeed("test -e /nix/var/.late")
  '';
}
