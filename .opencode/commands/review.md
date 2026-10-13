---
description: Review the current branch against main with the reviewer sub-agent.
agent: reviewer
subtask: true
---

Review this branch. $ARGUMENTS

Commits since the fork point:

!`git log --format='%h %s' $(git merge-base HEAD main)..HEAD`

Files changed, including uncommitted work:

!`git diff --stat $(git merge-base HEAD main)`

Coverage:

!`module-coverage || true`

Read the full diff yourself with `git diff $(git merge-base HEAD main)` and
return findings in the form your instructions give.
