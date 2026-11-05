#!/usr/bin/env python3
"""The hooks a Claude Code session in this repository runs.

usage: othrys-agent-hook pre-tool-use | post-tool-use

Claude Code hands each hook the tool call as JSON on standard input, and
.claude/settings.json runs this program before and after every write and
every shell command. None of it calls a model.

Before a write, the text bound for each file of this repository, in any of
its worktrees, goes through hygiene-scan, and a refusal stops the write. The
checks and docs sub-agents may write only inside the paths their roles own,
and the reviewer writes nothing. Before a shell command, a git command that
records history on main or points main elsewhere is refused, a sub-agent may
not run check-one, and the reviewer may run only the read-only commands its
role lists.

After a write, treefmt formats the file. In a session that wrote under
modules/, module-coverage runs and a missing check or page is reported once
for each distinct report. After a shell command, a main that moved anyway is
reported.

Only exit status 2 stops a call, so any failure of this program before a
write or a command exits 2 and stops it too.
"""

import fcntl
import fnmatch
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

WRITERS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
FORMATTED = {".nix", ".sh", ".toml", ".yaml", ".yml", ".md"}

# What each of the repository's sub-agents may write, by path from the root
# of the worktree. The reviewer writes nothing. Claude Code's own sub-agents
# and the main session are not limited here.
ROLE_SCOPES = {
    "checks": ["flake/checks/*", ".github/workflows/build.yml", "docs/src/development/ci.md"],
    "docs": ["docs/*", "README.md"],
    "reviewer": [],
}
REVIEWER_GIT = {"diff", "log", "show", "status", "merge-base"}
REVIEWER_TOOLS = {"hygiene-scan", "module-coverage"}
# Options that make a read-only git command run or write something else.
REVIEWER_UNSAFE = ("--output", "--ext-diff", "--textconv", "--exec", "-o")

# A git command that records history, which is refused while main is checked
# out. Only a maintainer moves main, by a fast-forward to a reviewed and
# signed head.
RECORDS = {"commit", "merge", "cherry-pick", "rebase", "reset", "revert", "am", "pull"}
MAIN = {"main", "refs/heads/main"}
OPERATORS = {"&&", "||", ";", "|", "&", "|&", ";;", "(", ")"}
REDIRECTS = re.compile(r"^[0-9]*[<>]")
SUBSTITUTION = re.compile(r"\$\(([^()]*)\)|`([^`]*)`")
HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n.*?\n\s*\2[ \t]*(?=\n|$)", re.S)


class Refusal(Exception):
    """A reason to stop the call, shown to the model."""


def git(directory, *args):
    result = subprocess.run(["git", "-C", str(directory), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def common_dir(directory):
    found = git(directory, "rev-parse", "--path-format=absolute", "--git-common-dir")
    return Path(found).resolve() if found else None


def repository(payload):
    start = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    top = git(start, "rev-parse", "--show-toplevel")
    return Path(top) if top else Path(start)


class State:
    """What one session wrote and was told, kept beside the repository's git data.

    Hooks of the main session and of background sub-agents run at the same
    time, so the file is read, changed and written under one lock.
    """

    def __init__(self, root, session):
        base = common_dir(root) or root / ".git"
        name = re.sub(r"[^A-Za-z0-9_-]", "_", session or "session")
        self.path = base / "othrys-agent" / f"{name}.json"

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = open(self.path.with_suffix(".lock"), "w")
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        try:
            self.data = json.loads(self.path.read_text())
        except (OSError, ValueError):
            self.data = {}
        return self

    def __exit__(self, kind, value, trace):
        if kind is None or kind is Refusal:
            self.path.write_text(json.dumps(self.data))
        fcntl.flock(self.lock, fcntl.LOCK_UN)
        self.lock.close()


def replace(text, old, new, every):
    """Apply one exact edit, refusing a match the tool would resolve differently."""
    if not isinstance(old, str) or not isinstance(new, str):
        raise Refusal("Cannot reconstruct edit. old_string and new_string must be strings.")
    if old == "":
        return new
    ending = "\r\n" if "\r\n" in text else "\n"
    old = old.replace("\r\n", "\n").replace("\n", ending)
    new = new.replace("\r\n", "\n").replace("\n", ending)
    count = text.count(old)
    if count == 0 or (count > 1 and not every):
        raise Refusal("Cannot reconstruct edit. Use an exact, unique old_string or replace_all.")
    return text.replace(old, new) if every else text.replace(old, new, 1)


def read(path):
    try:
        return Path(path).read_text()
    except FileNotFoundError:
        return ""


def prospective(tool, args):
    """The text each file holds once the tool has run."""
    path = args.get("notebook_path") if tool == "NotebookEdit" else args.get("file_path")
    if not isinstance(path, str) or not path:
        raise Refusal(f"Cannot reconstruct {tool}. The path is missing.")
    if tool == "Write":
        if not isinstance(args.get("content"), str):
            raise Refusal("Cannot reconstruct Write. The content is missing.")
        return [(path, args["content"])]
    if tool == "NotebookEdit":
        # A cell lands inside the notebook's JSON, so the whole notebook is
        # scanned with the new cell beside it.
        return [(path, read(path) + "\n" + str(args.get("new_source", "")))]
    edits = [args] if tool == "Edit" else args.get("edits")
    if not isinstance(edits, list) or not edits:
        raise Refusal(f"Cannot reconstruct {tool}. The edits are missing.")
    text = "" if edits[0].get("old_string") == "" else read(path)
    for edit in edits:
        text = replace(text, edit.get("old_string"), edit.get("new_string"), bool(edit.get("replace_all")))
    return [(path, text)]


def inside(root, path):
    """The path from its worktree's root when the file belongs to this repository, else None."""
    target = Path(path)
    if not target.is_absolute():
        target = root / target
    directory = target.parent
    while not directory.exists() and directory != directory.parent:
        directory = directory.parent
    common = common_dir(directory)
    if common is None or common != common_dir(root):
        return None
    top = git(directory, "rev-parse", "--show-toplevel")
    if top is None:
        return None
    try:
        return target.resolve().relative_to(Path(top).resolve()).as_posix()
    except ValueError:
        return None


def check_write(root, payload, state):
    agent = payload.get("agent_type")
    for path, text in prospective(payload["tool_name"], payload.get("tool_input") or {}):
        target = inside(root, path)
        if target is None:
            continue
        if agent in ROLE_SCOPES and not any(fnmatch.fnmatch(target, glob) for glob in ROLE_SCOPES[agent]):
            raise Refusal(f"Refused. The {agent} sub-agent does not write {target}. Name the change in your reply instead.")
        if target.startswith("modules/"):
            state.data["touched"] = True
        scan = subprocess.run(["hygiene-scan", "-", target], input=text, capture_output=True, text=True, cwd=root)
        if scan.returncode != 0:
            raise Refusal(
                "Refused by hygiene-scan. This repository is public, see Public Hygiene in AGENTS.md.\n" + scan.stderr
            )


def segments(command):
    """Each simple command, with the inner commands of every substitution, as token lists."""
    command = HEREDOC.sub("<<HEREDOC", command)
    inner = []

    def lift(match):
        inner.append(match.group(1) if match.group(1) is not None else match.group(2))
        return "SUBSTITUTION"

    while SUBSTITUTION.search(command):
        command = SUBSTITUTION.sub(lift, command)
    out = []
    for text in [command, *inner]:
        lexer = shlex.shlex(text.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        current = []
        for token in lexer:
            if token in OPERATORS:
                if current:
                    out.append(current)
                current = []
            else:
                current.append(token)
        if current:
            out.append(current)
    return out


def invocation(tokens):
    """Split a git call into its directory, subcommand and arguments, or None."""
    start = next((i for i, t in enumerate(tokens) if t == "git" or t.endswith("/git")), None)
    if start is None:
        return None
    directory, globals_, rest = None, [], tokens[start + 1 :]
    while rest and rest[0].startswith("-"):
        option = rest.pop(0)
        globals_.append(option)
        if option in ("-C", "-c") and rest:
            value = rest.pop(0)
            globals_.append(value)
            if option == "-C":
                directory = value
    if not rest:
        return None
    return directory, globals_, rest[0], rest[1:]


def positional(args, valued=()):
    """The arguments that are not options or the values of the named options."""
    out, skip = [], False
    for arg in args:
        if skip:
            skip = False
        elif arg in valued:
            skip = True
        elif not arg.startswith("-"):
            out.append(arg)
    return out


def destination(refspec):
    return refspec.lstrip("+").split(":", 1)[1] if ":" in refspec else None


def moves_main(sub, args):
    """Why this git subcommand would move or replace main, or None."""
    flags = {a for a in args if a.startswith("-")}
    if sub == "branch":
        names = positional(args, ("-u", "--set-upstream-to", "-t", "--track"))
        if flags & {"-d", "-D", "--delete", "-m", "-M", "--move"} and MAIN & set(names):
            return "would delete or rename main"
        if flags & {"-c", "-C", "--copy"} and names and names[-1] in MAIN:
            return "would replace main with a copy"
        if flags & {"-f", "--force"} and names and names[0] in MAIN:
            return "would point main elsewhere"
    if sub in ("checkout", "switch"):
        for flag in ("-B", "-C", "--force-create"):
            if flag in args and args.index(flag) + 1 < len(args) and args[args.index(flag) + 1] in MAIN:
                return "would reset main"
        if any(a == "--force-create=main" for a in args):
            return "would reset main"
    if sub == "update-ref":
        refs = positional(args, ("-m",))
        if refs and refs[0] in MAIN:
            return "would rewrite main"
    if sub == "symbolic-ref" and MAIN & set(positional(args, ("-m",))):
        return "would point HEAD at main"
    if sub == "fetch" and any(destination(r) in MAIN for r in positional(args)):
        return "would fetch into main"
    if sub == "push":
        refs = positional(args, ("-o", "--push-option", "--repo"))
        if refs and refs[0] == "." and any(destination(r) in MAIN for r in refs[1:]):
            return "would push into main"
    if sub == "rebase":
        names = positional(args, ("--onto", "-s", "--strategy", "-X", "--strategy-option", "-x", "--exec"))
        if len(names) >= 2 and names[1] in MAIN:
            return "would rebase main"
    return None


def check_reviewer(command):
    lines = segments(command)
    if not lines:
        raise Refusal("Refused. The reviewer runs only " + ", ".join(sorted(REVIEWER_GIT | REVIEWER_TOOLS)) + ".")
    for tokens in lines:
        if any(REDIRECTS.match(t) for t in tokens):
            raise Refusal("Refused. The reviewer does not redirect output into files.")
        if tokens[0] in REVIEWER_TOOLS:
            continue
        call = invocation(tokens) if tokens[0] == "git" else None
        if call is None or call[1] or call[2] not in REVIEWER_GIT:
            raise Refusal("Refused. The reviewer runs only git " + ", ".join(sorted(REVIEWER_GIT)) + ", "
                          + " and ".join(sorted(REVIEWER_TOOLS)) + ".")
        if any(a.startswith(REVIEWER_UNSAFE) for a in call[3]):
            raise Refusal("Refused. The reviewer does not run git options that write files or run programs.")


def check_command(root, payload, state):
    command = str((payload.get("tool_input") or {}).get("command", ""))
    agent = payload.get("agent_type")
    if agent and re.search(r"\bcheck-one\b", command):
        raise Refusal("Refused. A sub-agent never evaluates. Return the check's name and let the caller run it.")
    try:
        lines = segments(command)
    except ValueError:
        if re.search(r"\bgit\b", command) or agent == "reviewer":
            raise Refusal("Refused. The command could not be read, so its git calls could not be checked. "
                          "Run them as separate commands.")
        lines = []
    if agent == "reviewer":
        check_reviewer(command)
    directory, on_main = root, None
    for tokens in lines:
        if tokens[0] == "cd" and len(tokens) > 1:
            directory = (directory / tokens[1]).resolve() if not tokens[1].startswith("/") else Path(tokens[1])
            on_main = None
            continue
        call = invocation(tokens)
        if call is None:
            continue
        where, _, sub, args = call
        here = (directory / where) if where and not where.startswith("/") else Path(where) if where else directory
        reason = moves_main(sub, args)
        if reason:
            raise Refusal(f"Refused. This command {reason}, which only a maintainer does.")
        if sub in ("switch", "checkout") and positional(args)[:1] == ["main"] and not {"-b", "-c"} & set(args):
            on_main = True
            continue
        branch = on_main if on_main is not None else git(here, "symbolic-ref", "--short", "-q", "HEAD") == "main"
        if branch and (sub in RECORDS or (sub == "stash" and "pop" in args)):
            raise Refusal("Refused. This would record history on main. Create a branch with "
                          "`git switch -c <name>` and work there.")
    state.data["main"] = git(root, "rev-parse", "--verify", "--quiet", "refs/heads/main")


def pre_tool_use(payload):
    root = repository(payload)
    with State(root, payload.get("session_id")) as state:
        tool = payload.get("tool_name")
        if tool == "Bash":
            check_command(root, payload, state)
        elif tool in WRITERS:
            check_write(root, payload, state)


def post_tool_use(payload):
    root = repository(payload)
    tool = payload.get("tool_name")
    notes = []
    with State(root, payload.get("session_id")) as state:
        if tool == "Bash":
            now = git(root, "rev-parse", "--verify", "--quiet", "refs/heads/main")
            before = state.data.get("main", now)
            if now != before:
                notes.append(
                    f"main moved from {before or 'nothing'} to {now or 'nothing'} during this command. "
                    "Only a maintainer moves main. Stop, and report this to the user with both commits."
                )
            state.data["main"] = now
        elif tool in WRITERS:
            args = payload.get("tool_input") or {}
            path = args.get("notebook_path") if tool == "NotebookEdit" else args.get("file_path")
            target = inside(root, path) if isinstance(path, str) else None
            if target is not None and Path(path).resolve().is_relative_to(root.resolve()) \
                    and Path(target).suffix in FORMATTED:
                fmt = subprocess.run(["treefmt", "--quiet", target], capture_output=True, text=True, cwd=root)
                if fmt.returncode != 0:
                    notes.append(f"treefmt could not format {target}:\n{fmt.stderr.strip()}")
            if state.data.get("touched"):
                coverage = subprocess.run(["module-coverage"], capture_output=True, text=True, cwd=root)
                report = coverage.stdout.strip()
                if coverage.returncode == 0:
                    state.data.pop("reminded", None)
                elif state.data.get("reminded") != report:
                    state.data["reminded"] = report
                    notes.append(
                        "module-coverage reports that this branch is not finished:\n" + report + "\n"
                        "A module change is finished when its check and its page changed with it. "
                        "Write what is missing before you stop, or say why this change needs neither."
                    )
    if notes:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "\n\n".join(notes)}}))


def main(argv):
    if len(argv) != 2 or argv[1] not in ("pre-tool-use", "post-tool-use"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        payload = json.loads(sys.stdin.read())
        (pre_tool_use if argv[1] == "pre-tool-use" else post_tool_use)(payload)
    except Refusal as reason:
        print(reason, file=sys.stderr)
        return 2
    except Exception as error:  # noqa: BLE001, a hook that fails must stop the call
        if argv[1] == "post-tool-use":
            print(f"othrys-agent-hook: {error}", file=sys.stderr)
            return 1
        print(f"Refused. othrys-agent-hook failed, so the call was not checked: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
