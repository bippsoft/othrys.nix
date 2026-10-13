#!/usr/bin/env python3
"""Exercise inline permissions and hygiene scanning without changing the checkout."""

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def run(*args, cwd, status=0, contains=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    assert result.returncode == status, (args, result.stdout, result.stderr)
    if contains is not None:
        assert contains in result.stdout + result.stderr, (args, result.stdout, result.stderr)
    return result


def configuration(root, fixture):
    shutil.copytree(root / ".opencode", fixture / ".opencode")
    for directory in (fixture / ".opencode").rglob("*"):
        if directory.is_dir():
            directory.chmod(0o755)
    original = json.loads((root / "opencode.json").read_text())

    def validate(config, status=0, contains=None):
        (fixture / "opencode.json").write_text(json.dumps(config))
        run("opencode-config", str(fixture), cwd=fixture, status=status, contains=contains)

    for name in ("general", "explore"):
        config = json.loads(json.dumps(original))
        config["agent"][name]["permission"]["bash"]["check-one*"] = "refuse"
        validate(config, 1, f"agent.{name}.permission.bash.check-one*")

        config = json.loads(json.dumps(original))
        config["agent"][name]["permission"]["task"] = {"missing-agent": "allow"}
        validate(config, 1, f"agent.{name}.permission.task names 'missing-agent'")

    config = json.loads(json.dumps(original))
    config["agent"]["fixture-agent"] = {"mode": "primary", "permission": {"edit": "deny"}}
    config["agent"]["general"]["permission"]["task"] = {"fixture-agent": "allow"}
    config["permission"]["task"] = {"fixture-agent": "allow"}
    config["default_agent"] = "fixture-agent"
    (fixture / ".opencode/commands/fixture.md").write_text(
        "---\ndescription: Read a fixture.\nagent: fixture-agent\n---\nRead the fixture.\n"
    )
    (fixture / ".opencode/agents/fixture.md").write_text(
        "---\ndescription: Read a fixture.\npermission:\n  task:\n    fixture-agent: allow\n---\nRead the fixture.\n"
    )
    validate(config)
    config["agent"]["fixture-agent"] = "invalid"
    validate(config, 1, "agent.fixture-agent is not a mapping")
    config["agent"] = []
    validate(config, 1, "agent is not a mapping")


def hygiene(fixture):
    run("git", "init", "--quiet", cwd=fixture)
    # Commit identity is process-local and uses placeholders.
    commit = (
        "git", "-c", "user.name=alice", "-c", "user.email=alice@example.com",
        "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture",
    )
    old = fixture / "before.txt"
    old.write_text("placeholder\n" * 40)
    run("git", "add", "before.txt", cwd=fixture)
    run(*commit, cwd=fixture)
    new = fixture / "after with spaces.txt"
    old.rename(new)
    address = "alice@" + "fixture.invalid"
    new.write_text(new.read_text() + address + "\n")
    run("git", "add", "-A", cwd=fixture)
    status = run("git", "diff", "--cached", "--name-status", "-M", cwd=fixture).stdout
    assert status.startswith("R"), status
    run("hygiene-scan", cwd=fixture, status=1, contains=new.name)

    # CI passes filenames after committing its checkout, so its index is clean.
    run(*commit, cwd=fixture)
    assert not run("git", "diff", "--cached", "--name-only", cwd=fixture).stdout
    run("hygiene-scan", new.name, cwd=fixture, status=1, contains=new.name)
    new.write_text("alice@example.com\n")
    run("hygiene-scan", new.name, cwd=fixture)
    new.write_text("ipv6@" + "dynv6.com\n")
    run("hygiene-scan", new.name, cwd=fixture)
    new.write_text("alice@" + "dynv6.com\n")
    run("hygiene-scan", new.name, cwd=fixture, status=1, contains=new.name)


if __name__ == "__main__":
    root = Path(sys.argv[1])
    with tempfile.TemporaryDirectory() as directory:
        fixture = Path(directory)
        configuration(root, fixture)
    with tempfile.TemporaryDirectory() as directory:
        hygiene(Path(directory))
    print("opencode-regressions: inline permissions, agent references and hygiene scans passed")
