# modules/lib/types.nix
# Shared option types for the othrys module tree, imported directly by the
# modules that need them rather than threaded through specialArgs (the consumer
# contract keeps specialArgs to `inputs` alone).
{lib}: {
  # A runtime path to credential material, produced by a secrets provider at
  # boot and read by a service at start.
  #
  # lib.types.path is the wrong type for these. It accepts a path literal such
  # as ./secrets/token, and a path literal becomes a world-readable /nix/store
  # entry the moment it is interpolated into a derivation. Note that the store
  # copy happens at interpolation rather than at toString, since `toString ./x`
  # still yields the source path, so checking a string prefix against storeDir
  # cannot catch a literal. The value has to be rejected by kind instead, which
  # is why this type is built on str and refuses paths outright.
  secretPath =
    lib.types.addCheck lib.types.str
    (v: lib.hasPrefix "/" v && !lib.hasPrefix "${builtins.storeDir}/" v)
    // {
      description = ''absolute runtime path outside the Nix store, e.g. "/run/secrets/service-password"'';
    };
}
