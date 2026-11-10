# modules/lib/ollama.nix
# The address the Ollama modules hand the server
#
# Imported directly like types.nix rather than threaded through specialArgs.
{lib}: {
  # Both upstream modules join host and port with a colon and no brackets,
  # which Ollama cannot split for an IPv6 address, so one is bracketed here.
  # The client side is net.nix's local, read from the merged upstream values.
  serverHost = host:
    if lib.hasInfix ":" host && !lib.hasPrefix "[" host
    then "[${host}]"
    else host;
}
