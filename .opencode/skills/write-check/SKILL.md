---
name: write-check
description: Write or extend a check under flake/checks that reads a module's behaviour back from an evaluated host. Use when a module is added or changed, or when an option has no expectation that would fail if it broke.
metadata:
  opencode/slash: "true"
---

A check proves what a module wrote. That a host evaluates proves almost
nothing, so the default form is a set of expectations read from the evaluated
configuration.

**Helpers**, defined in `flake/checks/default.nix`:

- `hostConfig [modules]` returns the evaluated `config` of a host built the
  way a consumer builds one.
- `mkExpectations "<name>" { "<label>" = <bool>; }` fails naming every false
  label.
- `rejectedWith "<fragment>" cfg` is true when the host carries a failing
  assertion whose message contains the fragment.
- `bootBase` is the least a host needs to evaluate, and `functioningHost` adds
  a managed user, nix settings and git.

**Steps:**

1. Read `flake/checks/opencode-eval.nix` or `flake/checks/gh-eval.nix` and copy
   the shape. Line 1 is the file's path and line 2 says `CORE` or `EXTENDED`
   and what the check reads.
2. Write one expectation per behaviour. The label is a sentence that is true
   when the module works, such as `"the token directory is persisted at mode 0700"`. Compare against a literal value, never against the module's own
   option default.
3. Cover the refusals. Each assertion in the module gets a `rejectedWith`
   expectation on a host that should trip it.
4. Cover the absent case. A host with the module off, or with no managed
   user, writes nothing.
5. Register the check in `flake/checks/default.nix` beside its neighbours,
   passing only the helpers it uses.
6. List it in `.github/workflows/build.yml`. An evaluation goes in the CORE
   list. A VM test goes in the extended matrix. `ci-coverage` fails when a
   check is in neither.
7. Add its row to the table in `docs/src/development/ci.md`.

A VM test is for behaviour that exists only at run time, such as a service
that must start or a file a unit writes. Read `flake/checks/keyring.nix` for
the form, and keep `specialArgs` to `{inherit inputs;}` or nothing.

Run the result with `check-one <name>`, one check at a time. A sub-agent hands
the name back to its caller and does not run it.
