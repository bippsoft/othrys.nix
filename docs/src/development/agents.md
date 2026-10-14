# Agent Sessions

The repository carries a configuration for [OpenCode](https://opencode.ai), so
that an agent working here is held to the same rules as a person. It is
maintainer tooling. An outside contributor may use it, and `AI_POLICY.md` at
the repository root applies in full to what they submit.

A session starts inside `nix develop`, since the dev shell provides the
language server, the formatter and three commands the session depends on.

## Layout

| Path | Holds |
|------|-------|
| `AGENTS.md` | The instructions every agent reads, which are the consumer contract, the public hygiene rules and the writing conventions |
| `opencode.json` | The commands an agent is denied, the formatter and the language server |
| `.opencode/agents/` | One primary agent and three sub-agents |
| `.opencode/skills/` | Eight procedures, each also a slash command |
| `.opencode/commands/` | Two commands that read the repository's state before they run |
| `.opencode/plugins/othrys.js` | The two automatic steps |

## Agents

`module` is a primary agent for a change under `modules/`. It writes the module
itself and hands the check, the page and the review to sub-agents, in that
order. It may call those three and the built-in `explore`, and no other.

| Sub-agent | May edit | Does |
|-----------|----------|------|
| `checks` | `flake/checks/`, the build workflow and the CI page | Writes the check and returns its name |
| `docs` | `docs/` and `README.md` | Writes the module's page |
| `reviewer` | Nothing | Reads the branch against the contract, hygiene and coverage, and returns findings |

The review is binding. For each finding the `module` agent either fixes it or
states why it stands, and it runs the review a second time after fixes. It
stops after the second round and lists what is left.

The built-in `build` agent stays the default for work that is not a module
change, such as an input update or a workflow fix.

## Skills and Commands

A skill is a procedure an agent loads when the work calls for it, and each is
also available as a slash command.

| Skill | For |
|-------|-----|
| `add-module` | A new module with its options, check and page |
| `change-module` | A change to options, defaults or behaviour, with the rules for a breaking one |
| `remove-module` | Removing a module and every reference to it |
| `document-module` | A module's page under `docs/src/modules/` |
| `write-check` | A check that reads a module's behaviour back from an evaluated host |
| `update-inputs` | Reading a `flake.lock` update and fixing what it breaks |
| `release` | Preparing a release for a maintainer to cut |
| `write-issue` | An issue in the four-heading form |

`/review` hands the current branch to the `reviewer` sub-agent, and `/status`
summarises open work, unreleased commits and the last runs on `main`.

## Automatic Steps

Four things happen without being asked for, and none of them calls a model.

- **Formatting.** After an edit, OpenCode runs `treefmt` on the file.
- **Hygiene.** Before a write, the plugin reconstructs each complete resulting
  file and passes it to `hygiene-scan`. It scans a renamed file under its
  destination path and applies multiedit replacements in order. It refuses a
  write when the scan fails or the result cannot be reconstructed exactly.
  Edits require exact matches, while patches require exact context and removed
  lines. The scan covers what a pattern can prove, which is an SSH flake URL,
  a sops-encrypted value, an age secret key, an address in `100.64.0.0/10`, and
  an e-mail address at a domain the tree does not already use. A hostname or a
  person's name passes it, which is why the `reviewer` reads for those. The same
  scan is a pre-commit hook, which receives filenames so it also scans CI's
  committed checkout. Running `hygiene-scan` without arguments scans staged
  contents, including renamed files.
- **Coverage.** After a write in a session that edited a module, the plugin
  runs `module-coverage`. If the branch changed a module and no check or no
  page, the result of that write says which is missing, once for each distinct
  report. The comparison is against `main`, and `OTHRYS_COVERAGE_BASE` names
  another branch for work stacked on one.
- **Main.** After every shell command, the plugin compares `main` with the
  commit it pointed at before. If it moved anyway, the result of that command
  says so and tells the agent to stop and report both commits.

## Limits

An agent works under limits that `opencode.json` and the agent files state as
denied commands.

- **One evaluation at a time.** `check-one <name>` builds a single check under
  one job and, where the user manager allows it, inside a memory-capped scope.
  It is the only route to an evaluation. `nix build`, `nix eval`, `nix flake check`, `nix develop` and `just` are denied, and a sub-agent is denied `check-one` as well.
  The defaults are one job, four cores and 16G, and `OTHRYS_CHECK_JOBS`,
  `OTHRYS_CHECK_CORES` and `OTHRYS_CHECK_MEMORY` change them.
- **No landing.** An agent commits unsigned on a branch. Pushing, tagging,
  signing and merging are denied, since every commit on `main` carries a
  maintainer's signature.
- **`main` stays put.** Renaming or force-moving a branch and rewriting a ref
  are denied. The plugin also refuses a git command that records history
  while `main` is checked out, and one that names `main` as the target of a
  branch move.

`just` is denied because a recipe is a line of shell in a file the agent can
edit. `check-one` is a store path, so an edit made during a session cannot
change what it runs.

The denied commands are a guard against the ordinary case and are not a
sandbox. A shell can reach `nix` in ways no pattern lists, and the signature
check on `main` is what holds when the patterns do not.

## Checks

`opencode-config` reads the configuration as files. It fails when a skill's
name does not match its directory, when an agent or a command has no
description, when a permission holds a value other than `allow`, `ask` or
`deny`, and when a file names an agent that does not exist. Permission checks
cover both Markdown agents and inline agents in `opencode.json`. Agent
references may name either form. The check also runs regression fixtures for
inline permissions, staged renames, clean-index filename scans and the plugin's
pre-write hook.
