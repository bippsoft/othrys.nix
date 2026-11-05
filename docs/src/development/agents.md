# Agent Sessions

The repository carries a configuration for
[Claude Code](https://code.claude.com/docs), so that an agent working here is
held to the same rules as a person. It is maintainer tooling. An outside
contributor may use it, and `AI_POLICY.md` at the repository root applies in
full to what they submit. Everything under `.claude/` is shared by every
contributor's session, and nothing in it is tailored to one person. A
contributor's own preferences, including whether a session may push, tag,
sign or merge, belong in their own `~/.claude/settings.json` or in
`.claude/settings.local.json`, which git ignores.

A session starts inside `nix develop`, since the dev shell provides the
language server, the formatter, the three commands the session depends on and
the hook program its settings run.

## Layout

| Path | Holds |
|------|-------|
| `AGENTS.md` | The instructions every session reads, which are the consumer contract, the public hygiene rules and the writing conventions |
| `.claude/settings.json` | The commands a session is denied and allowed, and the hooks that run before and after every write and shell command |
| `.claude/agents/` | Three sub-agents |
| `.claude/skills/` | Ten procedures, each also a slash command |
| `.claude/commands/` | One command that reads the branch before it runs |
| `flake/checks/agent-hook.py` | The hook program, built into the dev shell as `othrys-agent-hook` |

Claude Code reads `AGENTS.md` as project instructions when no `CLAUDE.md`
exists, so the repository keeps one file for every tool that reads it.

## Agents and the Module Skill

The `module` skill carries a change under `modules/` from the request to a
reviewed branch. It runs in the main session, since a sub-agent cannot hand
work to another one. The main session writes the module itself and hands the
check, the page and the review to sub-agents, in that order.

| Sub-agent | May write | Does |
|-----------|-----------|------|
| `checks` | `flake/checks/`, the build workflow and the CI page | Writes the check and returns its name |
| `docs` | `docs/` and `README.md` | Writes the module's page |
| `reviewer` | Nothing | Reads the branch against the contract, hygiene and coverage, and returns findings |

The hook program enforces each column. A write by one of these three outside
its paths is refused, measured from the root of whichever worktree of the
repository holds the file. The reviewer may run only `git diff`, `git log`,
`git show`, `git status`, `git merge-base`, `hygiene-scan` and
`module-coverage`, with no redirection and no option that writes a file or
runs another program, and every command it substitutes is held to the same
list. No sub-agent of any kind may run `check-one`. Claude Code's own
sub-agents, such as `general-purpose`, are not limited to a set of paths.

The review is binding. For each finding the main session either fixes it or
states why it stands, and it runs the review a second time after fixes. It
stops after the second round and lists what is left.

## Skills and Commands

A skill is a procedure a session loads when the work calls for it, and each is
also available as a slash command.

| Skill | For |
|-------|-----|
| `module` | Carrying one module change through its check, its page and a review |
| `add-module` | A new module with its options, check and page |
| `change-module` | A change to options, defaults or behaviour, with the rules for a breaking one |
| `remove-module` | Removing a module and every reference to it |
| `document-module` | A module's page under `docs/src/modules/` |
| `write-check` | A check that reads a module's behaviour back from an evaluated host |
| `update-inputs` | Reading a `flake.lock` update and fixing what it breaks |
| `release` | Preparing a release for a maintainer to cut |
| `write-issue` | An issue in the four-heading form |
| `status` | Summarising open work, unreleased commits and the last runs on `main` |

`release` and `status` run only when invoked by name. `status` reads GitHub
through `gh`, so each of its commands is left to the user's own permission
settings. `/review` hands the current branch to the `reviewer` sub-agent.

## Automatic Steps

`.claude/settings.json` runs `othrys-agent-hook` before and after every write
and every shell command. None of these steps calls a model.

- **The dev shell.** A write is refused when `othrys-agent-hook` is not on
  `PATH`, since nothing could scan it. Claude Code lets a call through when a
  hook command is missing or exits with any status but 2, so the settings put
  a shell test in front of the program, and the program exits 2 whenever it
  fails before a call.
- **Hygiene.** Before a write, the hook reconstructs each complete resulting
  file and passes it to `hygiene-scan` under its path in the repository. A
  file in another worktree of the repository is scanned the same way, and a
  file outside the repository is not scanned. It
  applies multiple edits in order, and it refuses a write when the scan fails
  or when an edit's old text is missing or not unique. The scan covers what a
  pattern can prove, which is an SSH flake URL, a sops-encrypted value, an age
  secret key, an address in `100.64.0.0/10`, and an e-mail address at a domain
  the tree does not already use. A hostname or a person's name passes it,
  which is why the `reviewer` reads for those. The same scan is a pre-commit
  hook, which receives filenames so it also scans CI's committed checkout.
  Running `hygiene-scan` without arguments scans staged contents, including
  renamed files. A file written by a shell command is not scanned before the
  write, and the pre-commit hook scans it when it is staged.
- **Formatting.** After a write, the hook runs `treefmt` on the file.
- **Coverage.** After a write in a session that edited a module, the hook runs
  `module-coverage`. If the branch changed a module and no check or no page,
  the session is told which is missing, once for each distinct report. The
  comparison is against `main`, and `OTHRYS_COVERAGE_BASE` names another
  branch for work stacked on one.
- **Main.** Before a shell command, the hook reads each git call in it,
  including those inside a substitution, with its directory from `git -C` or
  an earlier `cd`. It refuses a call that records history where `main` is
  checked out, or after the same command switched to `main`. It also refuses
  one that deletes, renames, resets or copies onto `main`, rewrites
  `refs/heads/main`, fetches or pushes into it, or rebases it. A command it
  cannot read is refused when it calls git. After the command, the hook
  compares `main` with the commit it pointed at before. If it moved anyway,
  the session is told to stop and report both commits. These refusals need
  the dev shell. Outside it the settings let a shell command through, while a
  write is still refused.

The hook keeps what it needs between calls, which is the head of `main` and
whether the session edited a module, in the repository's git directory under
`othrys-agent/`, and holds a lock on it while it reads and writes, since a
session and its background sub-agents run hooks at the same time.

## Limits

- **One evaluation at a time.** `check-one <name>` builds a single check under
  one job and, where the user manager allows it, inside a memory-capped scope.
  It is the only route to an evaluation, and `nix build`, `nix eval`,
  `nix flake check`, `nix develop`, `nix-build`, `nixos-rebuild` and `just`
  are denied. The defaults are one job, four cores and 16G, and
  `OTHRYS_CHECK_JOBS`, `OTHRYS_CHECK_CORES` and `OTHRYS_CHECK_MEMORY` change
  them.
- **`main` stays put.** A refusal from the hook stops a call before
  permission rules are read, so no allow rule in a user's own settings lets
  through a git command the hook refuses.
- **Landing.** Pushing, tagging, signing and merging are not configured here.
  They follow each user's own settings, and every commit on `main` still
  carries a maintainer's signature, which the `Commit signatures` job checks.

`just` is denied because a recipe is a line of shell in a file the session can
edit. `check-one` and `othrys-agent-hook` are store paths, so an edit made
during a session cannot change what they run.

The denied commands are a guard against the ordinary case and are not a
sandbox. A shell can reach `nix` in ways no pattern lists, and the signature
check on `main` is what holds when the patterns do not.

## Checks

`agent-config` reads the configuration as files. It fails when the settings
file is not valid JSON, when a permission list holds anything but rules, when
a hook runs `othrys-agent-hook` without the dev-shell test in front of it, and
when no hook refuses a write outside the dev shell. It fails when that gate
does not cover every tool that writes or runs the wrong step of the hook, and
when no hook runs the hook on shell commands or after a call. It also fails
when a skill's name does not match its directory, when an agent, a skill or a
command has no description or carries a key Claude Code does not read, when an
agent names a tool or a skill that does not exist, and when a command names an
agent that does not exist. It then runs the tests under pytest, which cover each refusal above, the
reconstruction of edits, the coverage reminder, broken copies of the settings
and the agents, and the staged-rename and clean-index cases of
`hygiene-scan`.
