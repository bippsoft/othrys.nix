# flake/checks/restic.nix
# EXTENDED. Backup data-safety proof through the othrys restic module. A real
# backup runs twice, the data is destroyed and restored, and the repository is
# then damaged to show that the check the unit itself runs catches it, since
# a safety net that cannot detect damage is decoration. The timer and the
# environment file are read back from the running units, and a repository
# URL that carries credentials has to be refused before any of it is built.
{
  pkgs,
  inputs,
  hostConfig,
  rejectedWith,
  bootBase,
}: let
  inherit (inputs.nixpkgs) lib;

  credentialUrl = hostConfig [
    bootBase
    {
      othrys.services.restic = {
        enable = true;
        backups.data = {
          paths = ["/srv/data"];
          repository = "rest:https://alice:hunter2@backup.example.com/repo";
          passwordFile = "/run/secrets/restic-password";
        };
      };
    }
  ];
in
  assert lib.assertMsg (rejectedWith "backups.data.repository carries credentials" credentialUrl)
  "othrys-restic-roundtrip: a repository URL with credentials in it was not rejected";
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
        environment.etc."restic-env".text = "RESTIC_PASSWORD=test-password-env";

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
          # The password comes from the environment file alone, and no timer
          # is wanted.
          backups.env = {
            paths = ["/srv/data"];
            repository = "/srv/backup-env";
            environmentFile = "/etc/restic-env";
            timerConfig = null;
          };
        };
      };

      testScript = {nodes, ...}: let
        # The check step exactly as the unit runs it, with the module's
        # default checkOpts, taken from the evaluated ExecStart list.
        unitCheck = lib.findFirst (lib.hasInfix " check ") (throw "the backup unit has no check step") nodes.machine.systemd.services."restic-backups-data".serviceConfig.ExecStart;
      in ''
        import json

        restic = "restic -r /srv/backup --password-file /etc/restic-pass"
        unit_check = "env RESTIC_REPOSITORY=/srv/backup RESTIC_PASSWORD_FILE=/etc/restic-pass ${unitCheck}"

        machine.start()
        machine.wait_for_unit("multi-user.target")

        with subtest("the timer carries the schedule"):
            machine.succeed("systemctl is-active restic-backups-data.timer")
            machine.succeed("systemctl cat restic-backups-data.timer | grep -F 'OnCalendar=daily'")
            machine.fail("systemctl cat restic-backups-env.timer")

        with subtest("backup captures the data (and the unit's check passes)"):
            machine.succeed("mkdir -p /srv/data")
            machine.succeed("echo precious > /srv/data/file")
            machine.succeed("dd if=/dev/urandom of=/srv/data/blob bs=1k count=64 status=none")
            machine.succeed("systemctl start restic-backups-data.service")

        with subtest("a second run adds a snapshot beside the first"):
            machine.succeed("echo more > /srv/data/second")
            machine.succeed("sha256sum /srv/data/* > /root/checksums")
            machine.succeed("systemctl start restic-backups-data.service")
            snapshots = json.loads(machine.succeed(f"{restic} snapshots --json"))
            assert len(snapshots) == 2, f"expected two snapshots after the second run, got {len(snapshots)}"

        with subtest("a backup reads its password from the environment file"):
            machine.succeed("systemctl cat restic-backups-env.service | grep -F 'EnvironmentFile=/etc/restic-env'")
            machine.succeed("systemctl start restic-backups-env.service")
            machine.succeed("RESTIC_PASSWORD=test-password-env restic -r /srv/backup-env snapshots")
            machine.fail("RESTIC_PASSWORD=wrong restic -r /srv/backup-env snapshots")

        with subtest("destroyed data restores byte-identically"):
            machine.succeed("rm -rf /srv/data")
            machine.succeed(f"{restic} restore latest --target /")
            machine.succeed("cd / && sha256sum -c /root/checksums")

        with subtest("a corrupted repository fails the unit's own check"):
            assert "--read-data-subset=5%" in unit_check, unit_check
            machine.succeed(unit_check)
            # Truncate every pack. The module's default check reads a random
            # 5% of the pack data, so it cannot be relied on to meet one
            # overwritten byte in a given run. It always compares every pack's
            # size with the index first, which is the damage produced here.
            machine.succeed(
                "for p in $(find /srv/backup/data -type f); do"
                " truncate -s -64 $p;"
                " done"
            )
            machine.fail(unit_check)
            machine.fail("systemctl start restic-backups-data.service")
      '';
    }
