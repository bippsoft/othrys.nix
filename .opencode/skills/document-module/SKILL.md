---
name: document-module
description: Write or update a module's page under docs/src/modules. Use after a module is added or changed, or when a page no longer matches the source.
metadata:
  opencode/slash: "true"
---

A module page tells the reader what the source does not show. The generated
reference at `docs/src/reference/options.md` already lists every option with
its type and default, and it is never edited by hand.

1. **Read first.** Read the module and its check. Every sentence on the page
   states what one of them does.
2. **Find the page.** Each category has one page under `docs/src/modules/`. A
   module gets a section there. A new page is also a new line in
   `docs/src/SUMMARY.md`, or `comment-hygiene` fails.
3. **Write the section in this order.**
   - What the module does, in two or three sentences.
   - What a host must set, with a minimal example using `alice` and
     `example.com`.
   - What the reader would get wrong from the option names alone. That is the
     defaults that surprise, the values the module refuses and why, what it
     persists, and what it leaves to the host.
   - `### Options`, embedding the option block through an anchor.
4. **Anchors.** A `.nix` region is embedded with `{{#include}}` and an anchor
   name, and the `.nix` file carries the matching `ANCHOR` and `ANCHOR_END`
   comments. Read Comments and Anchors in `CONTRIBUTING.md`. An anchor no page
   includes fails `comment-hygiene`.
5. **Other pages.** Update the README module table when a module is added or
   removed, and `docs/src/development/ci.md` when a check is.

Write in full sentences, in the present tense, and state behaviour as fact.
Describe the module as it is now. A page never narrates how the module
changed or how to migrate from an earlier default, since the changelog and the
commit's `BREAKING CHANGE:` footer do that.

Keep a section to what a reader needs to use the module. Name what the module
does not do only where a reader would assume that it does. A section about
one module rarely needs more than forty lines before its options.
