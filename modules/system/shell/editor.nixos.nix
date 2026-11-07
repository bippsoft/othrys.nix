# modules/system/shell/editor.nixos.nix
# The NixOS implementation of othrys.system.defaultEditor
{config, ...}: {
  imports = [./editor.nix];

  # The one place EDITOR and VISUAL are set. environment.variables reaches
  # every login shell of every user through /etc/set-environment, so neither
  # shell module exports its own copy and no editor module sets the variable
  # behind the option's back.
  config.environment.variables = {
    EDITOR = config.othrys.system.defaultEditor;
    VISUAL = config.othrys.system.defaultEditor;
  };
}
