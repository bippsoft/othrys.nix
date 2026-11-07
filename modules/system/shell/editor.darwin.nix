# modules/system/shell/editor.darwin.nix
# The nix-darwin implementation of othrys.system.defaultEditor
{config, ...}: {
  imports = [./editor.nix];

  # As on NixOS, the one place EDITOR and VISUAL are set. nix-darwin writes
  # environment.variables to its set-environment file, which the bash and
  # zsh it configures source at startup. A plain value also replaces its
  # EDITOR default of nano, which it sets at mkDefault.
  config.environment.variables = {
    EDITOR = config.othrys.system.defaultEditor;
    VISUAL = config.othrys.system.defaultEditor;
  };
}
