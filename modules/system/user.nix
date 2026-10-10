# modules/system/user.nix
# Primary user identity, exposed as a required option instead of a specialArg.
#
# Historically modules read a `username` specialArg threaded in by the consumer.
# That implicit coupling is gone. The primary user is now named explicitly via
# the mandatory `othrys.system.user.name` option. There is deliberately no
# default, since a host must state who its user is.
{lib, ...}: {
  options.othrys.system.user.name = lib.mkOption {
    # The name becomes an account, a home directory, an attribute key and an
    # argument in generated shell and tmpfiles lines, so it is held to the
    # portable login name form. A capital letter, a space or a leading digit
    # is refused while the option is read, before any module uses the value.
    type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
    # Required: no default. The primary user must be named explicitly rather
    # than inheriting a placeholder or a magic specialArg. An unset value fails
    # with the module system's "used but not defined" error.
    example = "alice";
    description = ''
      Login name of the primary user account. Modules that create per-user
      state (home-manager, persistence, git, ...) read this value. This option
      is mandatory, so set it in your host configuration.

      The name starts with a lowercase letter or an underscore, and continues
      with lowercase letters, digits, underscores and hyphens. Any other
      value is refused at evaluation.
    '';
  };
}
