#!/usr/bin/env python3
"""Validate the committed OpenCode configuration.

usage: opencode-config.py <repository root>

OpenCode skips a skill whose name does not match its directory, and runs an
agent or command without a description as if nothing were wrong. A file can
also name an agent that was renamed or removed. None of these stops OpenCode
from starting, so this reads the files and fails on each one.
"""

import json
import re
import sys
from pathlib import Path

import yaml

SKILL_NAME = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
AGENT_MODES = {"primary", "subagent", "all"}
# The agents OpenCode ships. A file may name these without defining them.
BUILT_IN_AGENTS = {"build", "plan", "general", "explore", "scout"}
ACTIONS = {"allow", "ask", "deny"}


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


def actions(path, where, value, errors):
    """Check that every leaf of a permission value is allow, ask or deny."""
    if isinstance(value, str):
        if value not in ACTIONS:
            errors.append(f"{path}: {where} is '{value}', not allow, ask or deny")
    elif isinstance(value, dict):
        for key, inner in value.items():
            actions(path, f"{where}.{key}", inner, errors)
    else:
        errors.append(f"{path}: {where} is neither an action nor a pattern map")


def task_names(permission):
    """The agent names a permission block grants or denies by exact name."""
    task = permission.get("task") if isinstance(permission, dict) else None
    if not isinstance(task, dict):
        return []
    return [name for name in task if not any(c in name for c in "*?")]


def main(root):
    errors = []
    base = root / ".opencode"

    config_path = root / "opencode.json"
    try:
        config = json.loads(config_path.read_text())
    except (OSError, json.JSONDecodeError) as err:
        print(f"{config_path}: {err}", file=sys.stderr)
        return 1
    actions(config_path, "permission", config.get("permission", {}), errors)

    inline = config.get("agent", {})
    if not isinstance(inline, dict):
        errors.append(f"{config_path}: agent is not a mapping")
        inline = {}
    for name, data in inline.items():
        if not isinstance(data, dict):
            errors.append(f"{config_path}: agent.{name} is not a mapping")
            continue
        actions(config_path, f"agent.{name}.permission", data.get("permission", {}), errors)

    agents = {}
    for path in sorted((base / "agents").glob("*.md")):
        data = frontmatter(path, errors)
        if data is None:
            continue
        agents[path.stem] = data
        description(path, data, errors)
        mode = data.get("mode", "all")
        if mode not in AGENT_MODES:
            errors.append(f"{path}: mode is '{mode}', not one of {sorted(AGENT_MODES)}")
        for old in ("tools", "maxSteps"):
            if old in data:
                errors.append(f"{path}: '{old}' is deprecated, use permission or steps")
        actions(path, "permission", data.get("permission", {}), errors)

    known = BUILT_IN_AGENTS | set(agents) | set(inline)

    for name, data in inline.items():
        if not isinstance(data, dict):
            continue
        for target in task_names(data.get("permission")):
            if target not in known:
                errors.append(f"{config_path}: agent.{name}.permission.task names '{target}', which is not an agent")

    for name, data in agents.items():
        for target in task_names(data.get("permission")):
            if target not in known:
                errors.append(f"{base / 'agents' / (name + '.md')}: permission.task names '{target}', which is not an agent")
    for target in task_names(config.get("permission")):
        if target not in known:
            errors.append(f"{config_path}: permission.task names '{target}', which is not an agent")
    default = config.get("default_agent")
    if default is not None and default not in known:
        errors.append(f"{config_path}: default_agent is '{default}', which is not an agent")

    for path in sorted((base / "commands").glob("*.md")):
        data = frontmatter(path, errors)
        if data is None:
            continue
        description(path, data, errors)
        agent = data.get("agent")
        if agent is not None and agent not in known:
            errors.append(f"{path}: agent is '{agent}', which is not an agent")

    skills = base / "skills"
    for directory in sorted(p for p in skills.iterdir() if p.is_dir()) if skills.is_dir() else []:
        path = directory / "SKILL.md"
        if not path.is_file():
            errors.append(f"{directory}: no SKILL.md")
            continue
        data = frontmatter(path, errors)
        if data is None:
            continue
        description(path, data, errors)
        name = data.get("name")
        if name != directory.name:
            errors.append(f"{path}: name is '{name}', and the directory is '{directory.name}'")
        elif not SKILL_NAME.match(name) or len(name) > 64:
            errors.append(f"{path}: '{name}' is not a valid skill name")
        metadata = data.get("metadata", {})
        if not isinstance(metadata, dict) or not all(isinstance(v, str) for v in metadata.values()):
            errors.append(f"{path}: metadata must map strings to strings")
        extra = set(data) - {"name", "description", "license", "compatibility", "metadata"}
        if extra:
            errors.append(f"{path}: unknown frontmatter keys {sorted(extra)}, put them under metadata")

    for err in errors:
        print(err, file=sys.stderr)
    if errors:
        return 1
    print(f"opencode-config: {len(agents)} agents and the skills and commands under {base} are sound")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(Path(sys.argv[1])))
