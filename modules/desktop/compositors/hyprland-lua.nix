# modules/desktop/compositors/hyprland-lua.nix
# Helpers for Hyprland's Lua config format. Not a NixOS module, just a plain
# function that modules contributing to
# `wayland.windowManager.hyprland.settings` import directly.
#
# Home Manager's Lua renderer turns every top-level `settings` attribute into
# an `hl.<name>(...)` call, where list values emit one call per element and an `_args`
# list becomes a multi-argument call, and `lib.generators.mkLuaInline` values
# are spliced in as raw Lua. These helpers cover the two shapes othrys modules
# need (a keybinding and a spawn dispatcher), so chord syntax and Lua string
# quoting live in one place instead of in every consumer.
{lib}: let
  toLua = lib.generators.toLua {};

  # Chords name the modifier as `$mainMod`. Render that as a reference to the
  # `mainMod` Lua local the hyprland module emits, so a consumer's chord
  # tracks the `mainMod` option instead of hardcoding SUPER. Chords without
  # the token stay plain Lua strings.
  luaChord = chord:
    if !(lib.hasInfix "$mainMod" chord)
    then chord
    else
      lib.generators.mkLuaInline (
        lib.concatStringsSep " .. " (
          lib.filter (s: s != "") (
            lib.intersperse "mainMod" (
              map (s:
                if s == ""
                then ""
                else toLua s) (lib.splitString "$mainMod" chord)
            )
          )
        )
      );
in {
  inherit luaChord;

  # The deferred spawn dispatcher, `exec` in hyprlang terms. Runs through
  # /bin/sh, so shell syntax ($(...), pipes, ~) still works.
  execCmd = cmd: "hl.dsp.exec_cmd(${toLua cmd})";

  # One `hl.bind(<chord>, <dispatcher>[, <opts>])` call. `dispatcher` is a raw
  # Lua expression (e.g. `hl.dsp.window.close()`); `opts` is hl.bind's option
  # table, holding `locked` (works while the screen is locked), `repeating` (key
  # repeat), `mouse` (click-and-drag binds), `description`, ...
  mkBind = {
    key,
    dispatcher,
    opts ? {},
  }: {
    _args =
      [
        (luaChord key)
        (lib.generators.mkLuaInline dispatcher)
      ]
      ++ lib.optional (opts != {}) opts;
  };
}
