# flake/checks/restic.nix
# EXTENDED. Backup data-safety proof through the othrys restic module. A real
# backup runs twice, the data is destroyed and restored, and the repository is
# then damaged to show that the check the unit itself runs catches it, since
# a safety net that cannot detect damage is decoration. The timer and the
# environment file are read back from the running units, and a repository
# URL that carries credentials has to be refused before any of it is built.
# A third backup runs as an unprivileged user against a repository named in a
# file, with a prepare and a cleanup command and a retention of one snapshot.
# A fourth completes its backup and fails its check, and the failure hook has
# to say that the check failed, and not the backup.
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

      nodes.machine = {
        imports = [
          inputs.self.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          inputs.impermanence.nixosModules.impermanence
        ];

        environment.etc."restic-pass".text = "test-password";
        environment.etc."restic-env".text = "RESTIC_PASSWORD=test-password-env";
        environment.etc."restic-repo".text = "/srv/backup-hooked";

        users.users.backup = {
          isSystemUser = true;
          group = "backup";
        };
        users.groups.backup = {};

        # Nothing listens on the discard port, so othrys-notify fails after
        # the failure hook has written its line to the journal.
        othrys.services.notify = {
          enable = true;
          url = "http://127.0.0.1:9";
        };

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
          # restic refuses the flag, so the backup completes and the check
          # step after it fails. Nothing is pruned in between.
          backups.checked = {
            paths = ["/srv/data"];
            repository = "/srv/backup-checked";
            passwordFile = "/etc/restic-pass";
            timerConfig = null;
            pruneOpts = [];
            checkOpts = ["--no-such-flag"];
          };
          # An unprivileged user, the repository from a file, both hooks,
          # and a retention that keeps one snapshot.
          backups.hooked = {
            paths = ["/srv/hooked"];
            repositoryFile = "/etc/restic-repo";
            passwordFile = "/etc/restic-pass";
            user = "backup";
            timerConfig = null;
            pruneOpts = ["--keep-last 1"];
            backupPrepareCommand = "id -un > /srv/hooked/prepared-by";
            backupCleanupCommand = "id -un > /srv/hooked-state/cleaned-by";
          };
        };
      };

      testScript = {nodes, ...}: let
        # The check step exactly as the unit runs it, with the module's
        # default checkOpts, taken from the evaluated ExecStart list. It is a
        # script of the module's own, so the options are read from the file.
        unitCheck = lib.findFirst (lib.hasSuffix "-check") (throw "the backup unit has no check step") nodes.machine.systemd.services."restic-backups-data".serviceConfig.ExecStart;
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

        with subtest("an unprivileged backup reads its repository from a file and runs both hooks"):
            hooked = "restic -r /srv/backup-hooked --password-file /etc/restic-pass"
            machine.succeed("install -d -o backup -g backup /srv/hooked /srv/backup-hooked /srv/hooked-state")
            machine.succeed("echo kept > /srv/hooked/file")
            machine.succeed("systemctl cat restic-backups-hooked.service | grep -F 'RESTIC_REPOSITORY_FILE=/etc/restic-repo'")
            machine.succeed("systemctl start restic-backups-hooked.service")
            assert machine.succeed("cat /srv/hooked/prepared-by").strip() == "backup"
            machine.wait_until_succeeds("test -s /srv/hooked-state/cleaned-by")
            assert machine.succeed("cat /srv/hooked-state/cleaned-by").strip() == "backup"
            assert machine.succeed("stat -c %U /srv/backup-hooked/config").strip() == "backup"
            # The prepare command ran before the snapshot was taken.
            machine.succeed(f"{hooked} ls latest | grep -F /srv/hooked/prepared-by")

        with subtest("the retention removes the older snapshot"):
            machine.succeed("systemctl start restic-backups-hooked.service")
            kept = json.loads(machine.succeed(f"{hooked} snapshots --json"))
            assert len(kept) == 1, f"expected one snapshot after the prune, got {len(kept)}"

        with subtest("a failed check after a completed backup is reported as a failed check"):
            hook = "restic-notify-failure@restic-backups-checked.service.service"
            machine.fail("systemctl start restic-backups-checked.service")
            taken = json.loads(machine.succeed("restic -r /srv/backup-checked --password-file /etc/restic-pass snapshots --json"))
            assert len(taken) == 1, f"expected the snapshot of the completed backup, got {len(taken)}"
            machine.wait_until_succeeds(f"journalctl -u '{hook}' --no-pager | grep -F 'the repository check after it failed'")
            machine.fail(f"journalctl -u '{hook}' --no-pager | grep -F 'no repository check ran'")

        with subtest("destroyed data restores byte-identically"):
            machine.succeed("rm -rf /srv/data")
            machine.succeed(f"{restic} restore latest --target /")
            machine.succeed("cd / && sha256sum -c /root/checksums")

        with subtest("a corrupted repository fails the unit's own check"):
            machine.succeed("grep -F -e '--read-data-subset=5%' ${unitCheck}")
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

        with subtest("a backup that cannot run is reported as a failed backup"):
            hook = "restic-notify-failure@restic-backups-hooked.service.service"
            machine.succeed("rm -rf /srv/backup-hooked && install -d -o root -g root -m 0700 /srv/backup-hooked")
            machine.fail("systemctl start restic-backups-hooked.service")
            machine.wait_until_succeeds(f"journalctl -u '{hook}' --no-pager | grep -F 'no repository check ran'")
            machine.fail(f"journalctl -u '{hook}' --no-pager | grep -F 'the repository check after it failed'")
      '';
    }
