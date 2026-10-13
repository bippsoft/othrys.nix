---
name: add-module
description: Add a new module under modules/ with its options, check and page. Use when a request names a program, service or setting that no othrys option covers yet.
metadata:
  opencode/slash: "true"
---

Read `docs/src/guides/adding-modules.md` and the Module Pattern, Package
Placement and Impermanence sections of `CONTRIBUTING.md` first. They hold the
template and the reasoning. The steps below are what those pages leave to you.

1. **Find the nearest module.** Pick one existing module of the same kind and
   read it whole. `modules/apps/cli/gh.nix` is the reference for an
   application and `modules/services/traefik.nix` for a service.
2. **Write the file.** Line 1 is `# <repository-relative path>` and line 2 is
   a comment saying what the module is for. The `comment-hygiene` hook refuses
   the file otherwise.
3. **Keep to the contract.** Per-user configuration goes to
   `othrys.internal.homeConfig."<category>.<name>"`. Persistent paths go to
   `othrys.internal.persist."<category>.<name>"`. A directory holding a token
   or a session takes `mode = "0700"`. Read the user from
   `config.othrys.system.user.name`.
4. **Refuse bad input by name.** A combination the module cannot serve gets an
   entry in `assertions` whose message names the option to change. Never let
   it fail deep inside nixpkgs.
5. **Import it** in the category's `default.nix`.
6. **Enable matrix.** `enable-matrix` turns on every `othrys.*.enable` option
   with defaults. A module that needs configuration to evaluate is listed in
   `expectedFail` in `flake/checks/enable-matrix.nix` with a fragment of its
   assertion.
7. **Check and page.** Follow `write-check` and `document-module`, or hand
   them to the `checks` and `docs` sub-agents when you run as `module`.

Use `alice` and `example.com` in every example and default.
