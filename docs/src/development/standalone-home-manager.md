# Design Spike: Standalone Home-Manager Export

Status: **assessed, not pursued** (revisit when a concrete non-NixOS machine
needs it). This page records the feasibility analysis so the next look
doesn't start from zero.

## The ask

Expose othrys' user-level configuration (editor, shells, git, CLI tools) as
`homeManagerModules` consumable by standalone home-manager, so work laptops,
other distros and darwin.

## Why it isn't a packaging exercise

Every home-manager fragment in this repository reads NixOS-scoped state
through `osConfig`:

- **Identity and guards.** `othrys.system.user.name`,
  `othrys.system.users.homeManaged`: the whole per-user guard architecture
  lives at the NixOS layer. Standalone HM has no `osConfig`; every gate
  would need an HM-scoped equivalent.
- **Cross-module signals.** `othrys.desktop.graphical`,
  `othrys.desktop.lockCommand`, `othrys.system.stylix.*`,
  `othrys.apps.languages.*`: the single-signal architecture is declared in
  NixOS options. Fragments consult these signals constantly (nixvim's
  palette fallback, yazi's clipboard dep, editor toolchain wiring).
- **Mixed-scope modules.** Most modules write *both* system and user
  config (languages installs toolchains via HM but is gated at the system
  layer, and stylix theming spans both). Splitting them is a rewrite rather than a
  refactor.

## What portability would take

A shared options layer: declare the `othrys.*` option *schemas* once in a
scope-neutral module imported by both the NixOS tree (as today) and an HM
tree (new), with fragments reading `config.othrys.*` from whichever scope
they're evaluated in instead of `osConfig`. Roughly:

1. Extract option declarations from ~20 modules into shared files.
2. Rewrite every `osConfig` read (~40 sites) to scope-relative reads.
3. Re-implement the guard semantics for HM scope (no accounts to guard, so
   `homeManaged` is trivially true, `graphical` becomes a consumer-set
   flag).
4. A parallel check matrix for the HM outputs.

Estimate: comparable to the headless-decoupling effort (a multi-session
refactor), touching every module with user-level state.

## Candidate surface (if pursued)

Genuinely portable content, in value order: nixvim (the whole tree),
zsh/starship/bash, git, yazi, gh, comma, the language toolchains. Not
portable: anything desktop (compositor-coupled), persistence (impermanence
is NixOS), services.

## Recommendation

**No-go for now.** The cost lands on every module while the benefit waits
on a machine that doesn't exist in the fleet yet. If one appears, do the
shared-options-layer refactor *first* as its own phase (it is also a
cleanliness win for the NixOS tree), then export the candidate surface
incrementally, starting with nixvim.
