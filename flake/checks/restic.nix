# flake/checks/restic.nix
# EXTENDED. Backup data-safety proof, running a real backup, then destroy, then
# restore roundtrip through the othrys restic module, plus the
# mutation test, corrupting the repository and assert `restic check`
# actually catches it (a safety net that can't detect damage is
# decoration).
{
  pkgs,
  inputs,
}:
pkgs.testers.runNixOSTest {
  name = "othrys-restic-roundtrip";
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

    environment.etc."restic-pass".text = "test-password";

    othrys.services.restic = {
      enable = true;
      backups.data = {
        paths = ["/srv/data"];
        repository = "/srv/backup";
        passwordFile = "/etc/restic-pass";
        initialize = true;
        runCheck = true;
        timerConfig = {OnCalendar = "daily";};
      };
    };
  };

  testScript = ''
    restic = "restic -r /srv/backup --password-file /etc/restic-pass"

    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("backup captures the data (and runCheck passes)"):
        machine.succeed("mkdir -p /srv/data")
        machine.succeed("echo precious > /srv/data/file")
        machine.succeed("dd if=/dev/urandom of=/srv/data/blob bs=1k count=64 status=none")
        machine.succeed("sha256sum /srv/data/* > /root/checksums")
        machine.succeed("systemctl start restic-backups-data.service")

    with subtest("destroyed data restores byte-identically"):
        machine.succeed("rm -rf /srv/data")
        machine.succeed(f"{restic} restore latest --target /")
        machine.succeed("cd / && sha256sum -c /root/checksums")

    with subtest("a corrupted repository fails restic check"):
        machine.succeed(f"{restic} check")
        # Truncate every pack. Plain `restic check` (the module's
        # runCheck default) verifies repository STRUCTURE, meaning pack
        # existence and size against the index, not pack contents,
        # in-place byte corruption is only caught by --read-data
        # (verified empirically against restic 0.19: tail-overwrite of
        # every pack passes plain check even with a cold cache).
        # Truncation is damage the default safety net provably catches.
        machine.succeed(
            "for p in $(find /srv/backup/data -type f); do"
            " truncate -s -64 $p;"
            " done"
        )
        machine.fail(f"{restic} check")
  '';
}
