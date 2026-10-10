# modules/apps/cli/nixvim/languages/conform.nix
# Builds the conform.nvim settings that run a registry formatter by store path
#
# conform resolves a formatter name to a built-in definition and looks its
# command up on the PATH. Setting `command` on the same name keeps the
# built-in arguments and replaces only the binary, so the editor runs the
# package the registry holds and not whatever the PATH resolves.
#
# The name follows the package's executable, since the arguments belong to
# the tool. A host that swaps alejandra for nixfmt gets conform's nixfmt
# definition, and a tool conform has no definition for runs bare on stdin.
# Two languages that share an executable name share one definition, so they
# must hold the same package.
{lib}: filetypes: formatter: let
  # Read from the metadata and not from the store path, since a string that
  # refers to a store path cannot be an attribute name.
  exe = formatter.meta.mainProgram or (lib.getName formatter);
  # conform names two definitions after something other than the executable.
  # ruff formats through its `format` subcommand, and the go package's main
  # program is the toolchain driver while gofmt sits beside it.
  renamed = {
    ruff = "ruff_format";
    go = "gofmt";
  };
  name = renamed.${exe} or exe;
  command =
    if exe == "go"
    then lib.getExe' formatter "gofmt"
    else lib.getExe formatter;
in {
  formatters_by_ft = lib.genAttrs filetypes (_: [name]);
  formatters.${name}.command = command;
}
