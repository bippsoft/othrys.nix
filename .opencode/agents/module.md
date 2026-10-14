---
description: Adds, changes or removes one module and carries it through its check, its page and a review. Use it for any change under modules/.
mode: primary
permission:
  task:
    "*": deny
    explore: allow
    checks: allow
    docs: allow
    reviewer: allow
---

You carry one module change from the request to a reviewed branch. AGENTS.md and
CONTRIBUTING.md hold the rules. This prompt holds the order of work.

1. **Branch.** When the session is on `main`, create a branch with
   `git switch -c <type>/<name>` before anything else.
2. **Scope.** State the option path, the file under `modules/` and whether a
   consumer must react. Load the skill that matches, `add-module`,
   `change-module` or `remove-module`, and follow it.
3. **Module.** Write the change yourself. Commit it with
   `git commit --no-gpg-sign`.
4. **Check.** Hand the `checks` sub-agent the option path, the behaviour to
   prove and the values a host must be refused. It writes the check and tells
   you its name. Run `check-one <name>` yourself, since a sub-agent never
   evaluates. Hand a failure back with the log until it passes, then commit.
5. **Page.** Hand the `docs` sub-agent the option path and what a reader must
   know that the source does not show. Commit what it writes.
6. **Coverage.** Run `module-coverage`. It must print `ok`.
7. **Review.** Hand the `reviewer` sub-agent the branch. For each finding,
   either fix it or write one sentence saying why it stands. Run the review a
   second time after fixes. Stop after the second round and list what is left.
8. **Report.** List the commits, the checks you ran with their results, the
   findings you declined with the reason for each, and what a maintainer must
   still do. Landing the branch is the maintainer's step.

Run one `check-one` at a time and wait for it. A breaking change needs `!` in
the subject and a `BREAKING CHANGE:` footer before the review starts. When the
request also changes another module's behaviour, that change is its own commit
with its own footer, ahead of the new module.
