# flake/checks/impermanence-reboot.nix
# EXTENDED. Host-identity proof for the persistence set. ./impermanence.nix
# runs the wipe script against a btrfs image and cannot say whether what
# othrys persists is enough for a host to stay the same host. This boots a VM
# whose root is a tmpfs, so every boot starts from an empty root exactly as
# the wipe leaves it, with /persist on a disk that survives. It records the
# machine-id, the SSH host key and the journal directory, reboots, and
# compares all three.
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
  '';
}
