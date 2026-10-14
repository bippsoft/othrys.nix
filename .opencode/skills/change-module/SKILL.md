---
name: change-module
description: Change an existing module's options, defaults or behaviour, including renames and breaking changes. Use for any edit to a file under modules/ that is not a new module or a whole removal.
metadata:
  opencode/slash: "true"
---

Decide first whether a consumer must react. That decision sets the commit type
and what else must change.

**A consumer must react** when an option is removed or renamed, a default
changes behaviour, a new option has no default, or a value that used to
evaluate is now refused. Then:

1. Mark the subject with `!` and add a `BREAKING CHANGE:` footer. The footer
   tells a consumer what to write in their host, with the old and the new
   option names.
2. A removed option keeps a `lib.mkRemovedOptionModule` entry in the module's
   `imports`, and its text names the replacement. A pure rename uses
   `lib.mkRenamedOptionModule`. `modules/apps/gui/ghostty.nix` shows the form.
3. `docs/src/architecture/stability.md` states how long a renamed option is
   kept. Follow it.

**In every case:**

1. Read the module's check before editing. Each expectation that names the
   behaviour you change must change in the same branch, and a new behaviour
   gets a new expectation.
2. Read the module's page under `docs/src/modules/` and bring it in line with
   the change.
3. Search for other readers of the option with a search for its dotted path
   across `modules/`, `flake/` and `templates/`.
4. When a default changes, state the old and the new value in the commit body.

Commit the module, the check and the page as separate commits with the types
`feat`, `fix` or `refactor`, then `test`, then `docs`. A request that also
changes how another module behaves gets that change in its own commit, with
its own `BREAKING CHANGE:` footer when it needs one. When the old behaviour
inferred something from the host, such as which application is enabled, keep
the inference unless the request asks to drop it.
