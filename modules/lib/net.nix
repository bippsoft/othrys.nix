# modules/lib/net.nix
# Address helpers shared by the service modules, imported directly like
# types.nix rather than threaded through specialArgs.
{lib}: {
  # The address a client on the same host connects to, given the address a
  # service binds. Several modules pair a listener with a local consumer, the
  # Prometheus scrape of its own node exporter, the Grafana datasource for
  # VictoriaMetrics, the journal upload into VictoriaLogs, and the consumer
  # has to be told where the listener is. Writing 127.0.0.1 breaks the moment
  # listenAddress is moved to one interface, since nothing then listens on
  # loopback, while writing listenAddress verbatim breaks on the unspecified
  # addresses, since 0.0.0.0 is not a destination.
  #
  # Contract: an unspecified address maps to the loopback of its family, an
  # IPv6 address is bracketed so it can be followed by a port, and anything
  # else is returned as it is. The result is a host for a URL or a host:port
  # target, never a bind address.
  local = addr:
    if addr == "0.0.0.0" || addr == ""
    then "127.0.0.1"
    else if addr == "::" || addr == "[::]"
    then "[::1]"
    else if lib.hasInfix ":" addr && !lib.hasPrefix "[" addr
    then "[${addr}]"
    else addr;
}
