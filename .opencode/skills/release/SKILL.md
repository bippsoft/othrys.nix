---
name: release
description: Prepare a release for a maintainer to cut, by reading the unreleased commits, the version commitizen derives and the changelog it would write. Use only when asked to prepare or check a release.
metadata:
  opencode/slash: "true"
  opencode/autoinvoke: "false"
---

A maintainer cuts the release, since the bump commit and the tag are signed.
You prepare it and stop before anything is committed.

1. **State.** `git status` is clean and the branch is `main`. `git describe --tags --abbrev=0` names the last tag.
2. **Unreleased commits.** `git log <last tag>..HEAD --format='%h %s'`. Each
   subject follows Conventional Commits. A breaking commit carries `!` and a
   `BREAKING CHANGE:` footer that tells a consumer what to do. Report any that
   does not, since a commit on `main` cannot be reworded.
3. **Version.** `cz bump --dry-run` prints the increment and the tag
   commitizen derives. Before 1.0 a breaking change moves the minor version.
4. **Changelog.** `cz changelog --dry-run --incremental --unreleased-version <tag>` prints the section. Read each breaking note as a consumer would. It
   must say what to change without the reader opening the commit.
5. **Open work.** `gh issue list --milestone <tag>` and `gh pr list`. Name
   anything still open under the milestone.
6. **Checks.** `gh run list --branch main --limit 3` shows whether the last
   push to `main` passed.

Report the derived tag, the changelog section, every commit whose message
needs attention, open milestone items, and the state of `main`. End with the
maintainer's commands from Releases in `docs/src/architecture/stability.md`.
