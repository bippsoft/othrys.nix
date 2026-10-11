# flake/checks/yubikey-onboard.nix
# EXTENDED. The packaged onboarding script's dry run, as an unprivileged user in a VM
#
# A VM and not a runCommand, because the script re-executes itself under
# `unshare -Urm` and mounts a ramfs there, and the build sandbox does not
# promise a nested user namespace. In the VM the namespace path is taken every
# time, and the test fails when it is not.
{
  pkgs,
  package,
}:
pkgs.testers.runNixOSTest {
  name = "othrys-yubikey-onboard-dry-run";

  nodes.machine = {
    users.users.alice.isNormalUser = true;
    environment.systemPackages = [package];
  };

  testScript = ''
    import re

    machine.start()
    machine.wait_for_unit("multi-user.target")

    # The working directory stands in for a public checkout. The backup
    # directory is named and must not be created, since a dry run writes
    # nothing. --force-volatile only keeps the test independent of which
    # filesystem the VM puts under /home.
    machine.succeed("su - alice -c 'mkdir /home/alice/checkout'")
    dry_run = (
        "cd /home/alice/checkout && yubikey-onboard --dry-run"
        " --name alice --email alice@example.com --expiry 2y --key-count 1"
        " --backup-dir /home/alice/backup --force-volatile </dev/null 2>&1"
    )

    with subtest("the dry run exits 0 inside its own namespace"):
        out = machine.succeed(f"su - alice -c '{dry_run}'")
        assert "Temporary GNUPGHOME is on ramfs" in out, (
            f"the dry run did not mount its ramfs: {out!r}"
        )
        assert "Could not mount ramfs" not in out, (
            f"the dry run fell back to tmpfs: {out!r}"
        )
        assert "Dry run complete" in out, f"the dry run did not finish: {out!r}"

    with subtest("the summary path is outside the working directory"):
        found = re.search(r"Summary would be saved under: (\S+)", out)
        assert found is not None, f"no summary path in the output: {out!r}"
        summary_dir = found.group(1)
        assert summary_dir == "/home/alice/backup", (
            f"unexpected summary directory: {summary_dir!r}"
        )
        assert not summary_dir.startswith("/home/alice/checkout"), (
            f"the summary would land in the working directory: {summary_dir!r}"
        )

    with subtest("the dry run wrote nothing"):
        # /tmp/xchg and /tmp/shared are the directories the test driver shares
        # with the VM, and they carry the build user's id.
        left = machine.succeed(
            "find /home/alice/checkout /tmp /dev/shm -mindepth 1 -user alice"
            " -not -path '/tmp/xchg*' -not -path '/tmp/shared*'"
        ).strip()
        assert left == "", f"the dry run left files behind: {left!r}"
        machine.fail("test -e /home/alice/backup")

    with subtest("a refused option prints its reason"):
        status, refused = machine.execute(
            "su - alice -c 'yubikey-onboard --algo dsa 2>&1'"
        )
        assert status == 1, f"expected exit 1, got {status}: {refused!r}"
        assert "Invalid algorithm: dsa" in refused, (
            f"the refusal carries no reason: {refused!r}"
        )
  '';
}
