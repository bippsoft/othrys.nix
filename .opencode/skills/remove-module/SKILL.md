---
name: remove-module
description: Remove a module and everything that names it. Use when a module is retired, replaced by another, or dropped with its upstream program.
metadata:
  opencode/slash: "true"
---

A removal always breaks consumers, so the subject carries `!` and the commit a
`BREAKING CHANGE:` footer that names the replacement or says there is none.

1. **List every reference.** Search for the option path and the file name
   across `modules/`, `flake/`, `templates/`, `docs/`, `README.md` and
   `.github/`. Work through the list and keep it for the report.
2. **Leave a removed-option entry.** Add
   `lib.mkRemovedOptionModule [...] "<what to do instead>"` to the `imports`
   of the category's `default.nix`, so a host that still sets the option fails
   with that sentence. `modules/apps/cli/ai/mcp/default.nix` shows the form.
3. **Delete the module** and its import line.
4. **Checks.** Remove the module's own check file, its entry in
   `flake/checks/default.nix`, its name in the CORE list or the extended
   matrix of `.github/workflows/build.yml`, and its row in
   `docs/src/development/ci.md`. Remove it from fixtures that enable it and
   from `expectedFail` in `enable-matrix.nix`. `ci-coverage` fails when the
   workflow and the checks disagree.
5. **Prove the refusal.** Add one expectation that a host setting the removed
   option is refused. `eval-types` or the category's check is the place.
6. **Pages.** Remove the module's section, its row in the README table and any
   link to it. `comment-hygiene` fails on a broken link and on an orphan page.
7. **Inputs.** When the module was the only user of a flake input, remove the
   input from `flake.nix` and `flake.lock` in its own commit.

Run `check-one` for `ci-coverage`, `pre-commit-check` and each check whose
fixture you touched.
