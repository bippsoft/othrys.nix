"""Tests for othrys-agent-hook and agent-config, run by the agent-config check under pytest.

Each hook test builds a throwaway repository, hands the hook a tool call as
Claude Code would, and reads back whether the call was stopped. The forbidden
address is assembled at run time so this file itself passes hygiene-scan.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

FORBIDDEN_DOMAIN = "fixture" + ".invalid"
FORBIDDEN = "alice@" + FORBIDDEN_DOMAIN
# Commit identity is process-local and uses placeholders, and signing is off
# since no key exists in the sandbox.
COMMIT = ["-c", "user.name=alice", "-c", "user.email=alice@example.com", "-c", "commit.gpgsign=false"]


def git(root, *args):
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)


@pytest.fixture
def root(tmp_path):
    repo = tmp_path / "repo"
    subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
    git(repo, *COMMIT, "commit", "-q", "--allow-empty", "-m", "init")
    (repo / "flake.lock").write_text("{}\n")
    return repo


def hook(root, event, tool, args, raw=None, **extra):
    payload = {"session_id": "fixture", "cwd": str(root), "tool_name": tool, "tool_input": args, **extra}
    env = {**os.environ, "CLAUDE_PROJECT_DIR": str(root)}
    return subprocess.run(["othrys-agent-hook", event], input=raw if raw is not None else json.dumps(payload),
                          capture_output=True, text=True, env=env)


def before(root, tool, args, **extra):
    return hook(root, "pre-tool-use", tool, args, **extra)


def after(root, tool, args, **extra):
    return hook(root, "post-tool-use", tool, args, **extra)


def refused(result, text):
    assert result.returncode == 2, (result.stdout, result.stderr)
    assert text in result.stderr, result.stderr


def allowed(result):
    assert result.returncode == 0, (result.stdout, result.stderr)


def context(result):
    allowed(result)
    return json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"] if result.stdout else ""


def bash(root, command, **extra):
    return before(root, "Bash", {"command": command}, **extra)


# Writes.

def test_edit_scans_the_address_assembled_from_an_existing_local_part(root):
    path = root / "contact.txt"
    path.write_text("alice@example.com\n")
    refused(before(root, "Edit", {"file_path": str(path), "old_string": "example.com", "new_string": FORBIDDEN_DOMAIN}),
            "Refused by hygiene-scan")
    assert path.read_text() == "alice@example.com\n"


def test_multiedit_scans_sequential_replacements_that_assemble_an_address(root):
    path = root / "contact.txt"
    path.write_text("contact: PLACEHOLDER\n")
    refused(before(root, "MultiEdit", {"file_path": str(path), "edits": [
        {"old_string": "PLACEHOLDER", "new_string": "alice@DOMAIN"},
        {"old_string": "DOMAIN", "new_string": FORBIDDEN_DOMAIN},
    ]}), "Refused by hygiene-scan")


def test_replace_all_scans_every_occurrence(root):
    path = root / "contact.txt"
    path.write_text("alice@PLACEHOLDER\nbob@PLACEHOLDER\n")
    refused(before(root, "Edit", {"file_path": str(path), "old_string": "PLACEHOLDER",
                                  "new_string": FORBIDDEN_DOMAIN, "replace_all": True}), "Refused by hygiene-scan")


def test_removing_forbidden_text_is_allowed(root):
    path = root / "contact.txt"
    path.write_text(FORBIDDEN + "\nlabel\n")
    allowed(before(root, "Edit", {"file_path": str(path), "old_string": FORBIDDEN + "\n", "new_string": ""}))


def test_an_empty_old_string_overwrites_rather_than_appends(root):
    path = root / "contact.txt"
    path.write_text(FORBIDDEN + "\n")
    allowed(before(root, "Edit", {"file_path": str(path), "old_string": "", "new_string": "alice@example.com\n"}))


def test_safe_exact_edits_and_crlf_normalization_are_allowed(root):
    path = root / "contact.txt"
    path.write_bytes(b"alice@example.com\r\nlabel\r\n")
    allowed(before(root, "Edit", {"file_path": str(path), "old_string": "example.com\nlabel",
                                  "new_string": "example.org\nlabel"}))


@pytest.mark.parametrize("old", ["label", "missing"])
def test_ambiguous_and_unmatched_edits_are_refused_before_scanning(root, old):
    path = root / "contact.txt"
    path.write_text("label\nlabel\n")
    refused(before(root, "Edit", {"file_path": str(path), "old_string": old, "new_string": "safe"}),
            "Cannot reconstruct edit")


def test_write_scans_the_complete_file(root):
    refused(before(root, "Write", {"file_path": str(root / "contact.txt"), "content": FORBIDDEN}),
            "Refused by hygiene-scan")
    allowed(before(root, "Write", {"file_path": str(root / "contact.txt"), "content": "alice@example.com\n"}))


def test_an_edit_scans_unchanged_contents_when_another_line_changes(root):
    path = root / "contact.txt"
    path.write_text(FORBIDDEN + "\nlabel\n")
    refused(before(root, "Edit", {"file_path": str(path), "old_string": "label", "new_string": "updated"}),
            "Refused by hygiene-scan")


def test_a_notebook_cell_is_scanned(root):
    path = root / "notes.ipynb"
    path.write_text('{"cells": []}\n')
    refused(before(root, "NotebookEdit", {"notebook_path": str(path), "new_source": FORBIDDEN}),
            "Refused by hygiene-scan")


def test_a_write_outside_the_repository_is_not_scanned(root, tmp_path):
    allowed(before(root, "Write", {"file_path": str(tmp_path / "note.txt"), "content": FORBIDDEN}))


def test_a_write_into_another_worktree_of_the_repository_is_scanned(root, tmp_path):
    git(root, "worktree", "add", "-q", "-b", "side", str(tmp_path / "side"))
    refused(before(root, "Write", {"file_path": str(tmp_path / "side/new/contact.txt"), "content": FORBIDDEN}),
            "Refused by hygiene-scan")


@pytest.mark.parametrize("tool,args,text", [
    ("Write", {"content": "text"}, "The path is missing"),
    ("Write", {"file_path": "/dev/null/x"}, "The content is missing"),
    ("Edit", {"file_path": "x", "old_string": 1, "new_string": "a"}, "must be strings"),
    ("MultiEdit", {"file_path": "x"}, "The edits are missing"),
])
def test_a_write_that_cannot_be_reconstructed_is_refused(root, tool, args, text):
    refused(before(root, tool, args), text)


def test_a_role_writes_only_inside_its_paths(root):
    target = root / "flake/checks/new-eval.nix"
    target.parent.mkdir(parents=True)
    allowed(before(root, "Write", {"file_path": str(target), "content": "{}\n"}, agent_type="checks"))
    refused(before(root, "Write", {"file_path": str(root / "modules/x.nix"), "content": "{}\n"}, agent_type="checks"),
            "The checks sub-agent does not write modules/x.nix")
    allowed(before(root, "Write", {"file_path": str(root / "docs/src/x.md"), "content": "text\n"}, agent_type="docs"))
    refused(before(root, "Write", {"file_path": str(root / "docs/src/x.md"), "content": "text\n"}, agent_type="reviewer"),
            "The reviewer sub-agent does not write")


def test_the_main_session_and_other_sub_agents_are_not_limited_to_a_role(root):
    allowed(before(root, "Write", {"file_path": str(root / "modules/x.nix"), "content": "{}\n"}))
    allowed(before(root, "Write", {"file_path": str(root / "modules/x.nix"), "content": "{}\n"},
                   agent_type="general-purpose"))


# Shell commands.

def test_a_sub_agent_never_evaluates(root):
    refused(bash(root, "check-one eval-gh", agent_type="checks"), "never evaluates")
    allowed(bash(root, "check-one eval-gh"))


def test_the_reviewer_runs_read_only_commands(root):
    for command in ["git diff $(git merge-base HEAD main) && module-coverage", "git log --oneline -3",
                    "git status", "hygiene-scan README.md"]:
        allowed(bash(root, command, agent_type="reviewer"))


@pytest.mark.parametrize("command,text", [
    ("git diff && rm -rf docs", "The reviewer runs only"),
    ("sed -i s/a/b/ README.md", "The reviewer runs only"),
    ("git difftool", "The reviewer runs only"),
    ("git show $(rm -rf docs)", "The reviewer runs only"),
    ("git show `rm -rf docs`", "The reviewer runs only"),
    ("git diff > README.md", "does not redirect"),
    ("git diff --output=README.md", "write files or run programs"),
    ("git -c diff.external=x diff", "The reviewer runs only"),
    ("", "The reviewer runs only"),
])
def test_the_reviewer_cannot_write_or_run_other_programs(root, command, text):
    refused(bash(root, command, agent_type="reviewer"), text)


@pytest.mark.parametrize("command", ["git commit -m change", "git merge feature", "git cherry-pick abc",
                                     "git reset --hard HEAD~1", "git rebase feature", "git revert abc",
                                     "git am fix.patch", "git pull", "git stash pop"])
def test_a_command_that_records_history_is_refused_on_main(root, command):
    refused(bash(root, command), "record history on main")


def test_switching_to_main_inside_the_command_is_seen(root):
    git(root, "switch", "-q", "-c", "feature")
    refused(bash(root, "git switch main && git commit -am x"), "record history on main")
    refused(bash(root, "git checkout main; git merge feature"), "record history on main")


def test_a_commit_in_a_worktree_on_main_is_refused(root, tmp_path):
    git(root, "switch", "-q", "-c", "feature")
    git(root, "worktree", "add", "-q", str(tmp_path / "trunk"), "main")
    refused(bash(root, f"git -C {tmp_path / 'trunk'} commit -m x"), "record history on main")
    refused(bash(root, f"cd {tmp_path / 'trunk'} && git commit -m x"), "record history on main")


def test_history_is_recorded_freely_on_a_branch(root):
    for command in ["git status", "git log main..HEAD", "git diff $(git merge-base HEAD main)",
                    "git branch -m main-notes notes"]:
        allowed(bash(root, command))
    git(root, "switch", "-q", "-c", "feature")
    for command in ["git commit -m change", "git rebase main", "git switch -c fix/x origin/main",
                    "git switch -C fix/x origin/main", "git branch -f feature main", "git fetch origin main",
                    "git push origin feature"]:
        allowed(bash(root, command))


@pytest.mark.parametrize("command", [
    "git branch -m feature main", "git branch -M main", "git branch --move main other", "git branch -f main HEAD",
    "git branch --force main HEAD", "git branch -q -f main HEAD", "git branch -D main", "git branch -d main",
    "git branch --delete main", "git branch -c feature main", "git branch -C feature main",
    "git branch --copy feature main", "git checkout -B main", "git checkout -q -B main", "git switch -C main",
    "git switch --force-create main", "git update-ref refs/heads/main HEAD",
    "git symbolic-ref HEAD refs/heads/main", "git fetch origin main:main", "git fetch . HEAD:main",
    "git fetch origin +feature:refs/heads/main", "git push . HEAD:main", "git rebase origin/main main",
    "git -C . branch -f main HEAD", "echo $(git branch -f main HEAD)",
])
def test_a_command_that_points_main_elsewhere_is_refused_from_any_branch(root, command):
    git(root, "switch", "-q", "-c", "feature")
    refused(bash(root, command), "which only a maintainer does")


def test_a_heredoc_body_does_not_hide_or_break_a_command(root):
    allowed(bash(root, "cat > note.txt <<'EOF'\nit's a note, git commit -m x\nEOF\ngit status"))


def test_an_unreadable_git_command_is_refused(root):
    refused(bash(root, "git commit -m 'unbalanced"), "could not be read")
    allowed(bash(root, "echo 'unbalanced"))


def test_a_main_that_moved_during_a_command_is_reported_once(root):
    allowed(bash(root, "true"))
    git(root, *COMMIT, "commit", "-q", "--allow-empty", "-m", "moved")
    assert "main moved from" in context(after(root, "Bash", {"command": "true"}))
    assert context(after(root, "Bash", {"command": "true"})) == ""


def test_the_coverage_reminder_is_given_once_for_each_report(root):
    git(root, "switch", "-q", "-c", "feature")
    module = root / "modules/x.nix"
    module.parent.mkdir()
    allowed(before(root, "Write", {"file_path": str(module), "content": "{}\n"}))
    module.write_text("{}\n")
    git(root, "add", "-A")
    git(root, *COMMIT, "commit", "-q", "-m", "module")
    first = context(after(root, "Write", {"file_path": str(module), "content": "{}\n"}))
    assert "module-coverage reports" in first, first
    assert context(after(root, "Write", {"file_path": str(module), "content": "{}\n"})) == ""


# Failures of the hook itself.

def test_unparseable_input_is_refused_before_a_call(root):
    refused(hook(root, "pre-tool-use", "Bash", {}, raw="not json"), "othrys-agent-hook failed")


def test_a_failure_inside_the_hook_is_refused_before_a_call(root):
    refused(before(root, "Write", "not an object"), "othrys-agent-hook failed")


def test_a_bad_subcommand_exits_two():
    result = subprocess.run(["othrys-agent-hook", "something"], input="{}", capture_output=True, text=True)
    assert result.returncode == 2


# hygiene-scan itself.

def run(*args, cwd, status=0, contains=None):
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    assert result.returncode == status, (args, result.stdout, result.stderr)
    if contains is not None:
        assert contains in result.stdout + result.stderr, (args, result.stdout, result.stderr)


def test_hygiene_scan_reads_staged_renames_and_named_files(root):
    old = root / "before.txt"
    old.write_text("placeholder\n" * 40)
    run("git", "add", "before.txt", cwd=root)
    run("git", *COMMIT, "commit", "--quiet", "-m", "fixture", cwd=root)
    new = root / "after with spaces.txt"
    old.rename(new)
    new.write_text(new.read_text() + FORBIDDEN + "\n")
    run("git", "add", "-A", cwd=root)
    status = subprocess.run(["git", "diff", "--cached", "--name-status", "-M"], cwd=root, capture_output=True,
                            text=True).stdout
    assert status.startswith("R"), status
    run("hygiene-scan", cwd=root, status=1, contains=new.name)

    # CI passes filenames after committing its checkout, so its index is clean.
    run("git", *COMMIT, "commit", "--quiet", "-m", "fixture", cwd=root)
    run("hygiene-scan", new.name, cwd=root, status=1, contains=new.name)
    new.write_text("alice@example.com\n")
    run("hygiene-scan", new.name, cwd=root)
    new.write_text("ipv6@" + "dynv6.com\n")
    run("hygiene-scan", new.name, cwd=root)
    new.write_text("alice@" + "dynv6.com\n")
    run("hygiene-scan", new.name, cwd=root, status=1, contains=new.name)


# agent-config.

@pytest.fixture
def configuration(tmp_path):
    source = Path(os.environ["OTHRYS_ROOT"]) / ".claude"
    shutil.copytree(source, tmp_path / ".claude")
    for path in (tmp_path / ".claude").rglob("*"):
        path.chmod(0o755 if path.is_dir() else 0o644)
    return tmp_path


def validate(root, status=0, contains=None):
    run("agent-config", str(root), cwd=root, status=status, contains=contains)


def test_the_committed_configuration_is_sound(configuration):
    validate(configuration)


def edit_settings(root, change):
    path = root / ".claude/settings.json"
    data = json.loads(path.read_text())
    change(data)
    path.write_text(json.dumps(data))


@pytest.mark.parametrize("change,text", [
    (lambda d: d["permissions"].update(deny="Bash(just *)"), "permissions.deny is not a list"),
    (lambda d: d["hooks"]["PreToolUse"][0]["hooks"][0].update(command="othrys-agent-hook pre-tool-use"),
     "without the dev-shell gate"),
    (lambda d: d["hooks"]["PreToolUse"][0]["hooks"][0].update(
        command="command -v othrys-agent-hook >/dev/null 2>&1 || exit 0; exec othrys-agent-hook pre-tool-use"),
     "refuses a write"),
    (lambda d: d["hooks"]["PreToolUse"][0]["hooks"][0].update(
        command=d["hooks"]["PreToolUse"][0]["hooks"][0]["command"].replace("pre-tool-use", "post-tool-use")),
     "refuses a write"),
    (lambda d: d["hooks"]["PreToolUse"][0].update(matcher="Write|Edit"), "does not cover NotebookEdit"),
    (lambda d: d["hooks"].pop("PostToolUse"), "no PostToolUse hook"),
])
def test_broken_settings_are_refused(configuration, change, text):
    edit_settings(configuration, change)
    validate(configuration, 1, text)


def test_a_broken_agent_or_skill_is_refused(configuration):
    agent = configuration / ".claude/agents/docs.md"
    agent.write_text(agent.read_text().replace("skills: [document-module]", "skills: [missing-skill]"))
    validate(configuration, 1, "names the skill 'missing-skill'")
    agent.write_text(agent.read_text().replace("tools: Read", "tools: Reed"))
    validate(configuration, 1, "'Reed', which is not a Claude Code tool")
    skill = configuration / ".claude/skills/release/SKILL.md"
    skill.write_text(skill.read_text().replace("name: release", "name: releases"))
    validate(configuration, 1, "name is 'releases', and the directory is 'release'")
