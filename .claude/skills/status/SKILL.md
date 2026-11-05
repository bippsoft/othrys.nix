---
name: status
description: Summarise the repository's open work, unreleased commits and the last runs on main. Use when asked where the repository stands.
disable-model-invocation: true
---

Summarise the state of the repository. $ARGUMENTS

Read these facts first. The last three read GitHub, so run each one as its
own command, which leaves each to the user's own permission settings.

- `git status --short --branch`
- `git describe --tags --abbrev=0`, then `git log --format='%h %s' <tag>..HEAD`
- `gh issue list --limit 30`
- `gh pr list --limit 30`
- `gh run list --branch main --limit 5`

Report, in this order: what is unreleased and whether any of it is breaking,
which pull requests are waiting and on what, which issues have no pull
request, and whether main is passing. State each as a fact with its number.
Change nothing.
