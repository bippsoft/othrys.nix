---
name: update-inputs
description: Read a flake.lock update and its check results, find what an input bump broke, and prepare the fix. Use on the weekly input update pull request or when a single input must move.
metadata:
  opencode/slash: "true"
---

The weekly workflow opens a pull request from `update_flake_lock_action` with
one unsigned commit. A maintainer signs it when landing it. Your work is to
say whether it is safe and to fix what it breaks.

1. **Read the bump.** `gh pr view <n>` lists each input with its old and new
   revision. Note which inputs moved.
2. **Read the results.** `gh pr checks <n>` lists every job. `Commit signatures` is skipped on this branch by design. Any other job that is not
   `pass` is a result to explain.
3. **Read a failure.** `gh run view <run> --job <job> --log` gives the log.
   Find the first error, and name the check, the module and the input that
   changed under it.
4. **Classify it.**
   - An option was renamed or removed upstream. The module needs a change, and
     the fix follows `change-module`.
   - An expectation compared against a value upstream changed on purpose. The
     check needs the new literal, and the commit body says what changed
     upstream.
   - A package fails to build upstream. Nothing here can fix it. Report the
     input and hold the bump.
5. **Fix on the bump.** Check out the pull request's commit, add the fix as
   further commits on top, and run `check-one` for each check that failed.
6. **A single input.** `nix flake update <input>` moves one input. State why
   it moves alone in the commit body, and commit `flake.lock` by itself with
   the type `chore` and the scope `flake`.

Report which inputs moved, each failing check with its cause, the commits you
added, and whether the bump is ready for a maintainer to sign.
