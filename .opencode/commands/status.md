---
description: Summarise the repository's open work, unreleased commits and the last runs on main.
---

Summarise the state of the repository from the facts below. $ARGUMENTS

Branch and working tree:

!`git status --short --branch`

Last tag and the commits since it:

!`git describe --tags --abbrev=0`

!`git log --format='%h %s' $(git describe --tags --abbrev=0)..HEAD`

Open issues:

!`gh issue list --limit 30`

Open pull requests:

!`gh pr list --limit 30`

Last runs on main:

!`gh run list --branch main --limit 5`

Report, in this order: what is unreleased and whether any of it is breaking,
which pull requests are waiting and on what, which issues have no pull
request, and whether main is passing. State each as a fact with its number.
Change nothing.
