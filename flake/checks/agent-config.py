#!/usr/bin/env python3
"""Validate the committed Claude Code configuration under .claude/.

usage: agent-config.py <repository root>

Claude Code ignores an unknown frontmatter key, loads a skill whose name
differs from its directory under that other name, and runs a hook command
that is not on PATH as a non-blocking error. None of these stops a session
from starting, so this reads the files and fails on each one.
"""

import json
import re
import sys
from pathlib import Path

import yaml

NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TOOLS = {
    "Agent", "Bash", "Edit", "Glob", "Grep", "MultiEdit", "NotebookEdit", "Read", "Skill", "TodoWrite",
    "WebFetch", "WebSearch", "Write",
}
AGENT_KEYS = {"name", "description", "tools", "disallowedTools", "model", "permissionMode", "maxTurns", "skills",
              "effort", "color", "isolation", "memory", "hooks", "mcpServers", "background", "initialPrompt",
              "autoCompactWindow", "omitClaudeMd"}
SKILL_KEYS = {"name", "description", "when_to_use", "argument-hint", "arguments", "disable-model-invocation",
              "user-invocable", "allowed-tools", "disallowed-tools", "model", "effort", "context", "agent",
              "background", "hooks", "paths", "shell", "license", "compatibility", "metadata"}
# The tools whose writes the hook scans, which the write gate must cover.
WRITERS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
COMMAND_KEYS = {"description", "argument-hint", "allowed-tools", "agent", "context", "model",
                "disable-model-invocation"}
# The repository's hook program, and the dev-shell gate in front of it.
HOOK = "othrys-agent-hook"
GATE = "command -v othrys-agent-hook >/dev/null 2>&1 ||"


def frontmatter(path, errors):
    """Return the YAML mapping that opens a Markdown file, or None."""
    text = path.read_text()
    if not text.startswith("---\n"):
        errors.append(f"{path}: does not open with a frontmatter block")
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        errors.append(f"{path}: the frontmatter block is not closed")
        return None
    try:
        data = yaml.safe_load(text[4:end])
    except yaml.YAMLError as err:
        errors.append(f"{path}: the frontmatter is not valid YAML ({err})")
        return None
    if not isinstance(data, dict):
        errors.append(f"{path}: the frontmatter is not a mapping")
        return None
    if not text[end + 5 :].strip():
        errors.append(f"{path}: the body is empty")
    return data


def description(path, data, errors, limit=1024):
    text = data.get("description")
    if not isinstance(text, str) or not text.strip():
        errors.append(f"{path}: no description")
    elif len(text) > limit:
        errors.append(f"{path}: the description is over {limit} characters")


def unknown(path, data, allowed, errors):
    extra = set(data) - allowed
    if extra:
        errors.append(f"{path}: unknown frontmatter keys {sorted(extra)}")


def tool_list(value):
    if isinstance(value, str):
        return [part.strip() for part in value.split(",") if part.strip()]
    return value if isinstance(value, list) else None


def settings(path, errors):
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as err:
        errors.append(f"{path}: {err}")
        return
    permissions = data.get("permissions", {})
    for kind in ("allow", "ask", "deny"):
        rules = permissions.get(kind, [])
        if not isinstance(rules, list) or not all(isinstance(r, str) and r for r in rules):
            errors.append(f"{path}: permissions.{kind} is not a list of rules")
    hooks = data.get("hooks", {})
    commands = []
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            errors.append(f"{path}: hooks.{event} is not a list")
            continue
        for group in groups:
            for entry in group.get("hooks", []) if isinstance(group, dict) else []:
                command = entry.get("command", "") if isinstance(entry, dict) else ""
                commands.append((event, group.get("matcher", ""), command))
                if HOOK in command and not command.startswith(GATE):
                    errors.append(f"{path}: hooks.{event} runs {HOOK} without the dev-shell gate in front of it")
    gates = [(set(m.split("|")), c) for e, m, c in commands if e == "PreToolUse"
             and c.startswith(GATE) and "exit 2" in c.split("exec")[0] and c.endswith(f"{HOOK} pre-tool-use")]
    if not gates:
        errors.append(f"{path}: no PreToolUse hook refuses a write when {HOOK} is missing and then runs pre-tool-use")
    for matched, _ in gates:
        for tool in sorted(WRITERS - matched):
            errors.append(f"{path}: the PreToolUse write gate does not cover {tool}")
    if not any(e == "PreToolUse" and "Bash" in m.split("|") and c.endswith(f"{HOOK} pre-tool-use")
               for e, m, c in commands):
        errors.append(f"{path}: no PreToolUse hook runs {HOOK} pre-tool-use on Bash")
    if not any(e == "PostToolUse" and c.endswith(f"{HOOK} post-tool-use") for e, m, c in commands):
        errors.append(f"{path}: no PostToolUse hook runs {HOOK} post-tool-use")


def main(root):
    errors = []
    base = root / ".claude"
    settings(base / "settings.json", errors)

    agents = {}
    for path in sorted((base / "agents").glob("*.md")):
        data = frontmatter(path, errors)
        if data is None:
            continue
        agents[path.stem] = data
        description(path, data, errors)
        unknown(path, data, AGENT_KEYS, errors)
        if data.get("name") != path.stem:
            errors.append(f"{path}: name is '{data.get('name')}', and the file is '{path.stem}'")
        tools = tool_list(data.get("tools", []))
        if tools is None:
            errors.append(f"{path}: tools is neither a list nor a comma-separated string")
        else:
            for tool in tools:
                if tool not in TOOLS and not tool.startswith("mcp__"):
                    errors.append(f"{path}: tools names '{tool}', which is not a Claude Code tool")

    for path in sorted((base / "commands").glob("*.md")):
        data = frontmatter(path, errors)
        if data is None:
            continue
        description(path, data, errors)
        unknown(path, data, COMMAND_KEYS, errors)
        agent = data.get("agent")
        if agent is not None and agent not in agents:
            errors.append(f"{path}: agent is '{agent}', which is not an agent under {base / 'agents'}")

    skills = base / "skills"
    names = {p.name for p in skills.iterdir() if p.is_dir()} if skills.is_dir() else set()
    for name, data in agents.items():
        listed = data.get("skills", [])
        for skill in listed if isinstance(listed, list) else [listed]:
            if skill not in names:
                errors.append(f"{base / 'agents' / (name + '.md')}: names the skill '{skill}', which is not under {skills}")
    for directory in sorted(p for p in skills.iterdir() if p.is_dir()) if skills.is_dir() else []:
        path = directory / "SKILL.md"
        if not path.is_file():
            errors.append(f"{directory}: no SKILL.md")
            continue
        data = frontmatter(path, errors)
        if data is None:
            continue
        description(path, data, errors)
        unknown(path, data, SKILL_KEYS, errors)
        name = data.get("name")
        if name != directory.name:
            errors.append(f"{path}: name is '{name}', and the directory is '{directory.name}'")
        elif not NAME.match(name) or len(name) > 64:
            errors.append(f"{path}: '{name}' is not a valid skill name")
        metadata = data.get("metadata", {})
        if not isinstance(metadata, dict) or not all(isinstance(v, str) for v in metadata.values()):
            errors.append(f"{path}: metadata must map strings to strings")

    for err in errors:
        print(err, file=sys.stderr)
    if errors:
        return 1
    print(f"agent-config: settings, {len(agents)} agents and the skills and commands under {base} are sound")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1])))
