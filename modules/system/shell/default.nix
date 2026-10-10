# modules/system/shell/default.nix
# Shell module aggregator
{
  config,
  lib,
  ...
}: {
  imports = [
    ./bash.nix
    ./zsh.nix
    ./starship.nix
  ];

  options.othrys.system.defaultEditor = lib.mkOption {
    type = lib.types.str;
    # vim ships in the essential package set (system/users.nix), and anything
    # fancier is the consumer's choice.
    default = "vim";
    description = "Default editor, used for EDITOR/VISUAL and git's core.editor. An editor module that wants to be the default sets it with mkDefault.";
  };

  # The one place EDITOR and VISUAL are set. environment.variables reaches
  # every login shell of every user through /etc/set-environment, so neither
  # shell module exports its own copy and no editor module sets the variable
  # behind the option's back.
  config.environment.variables = {
    EDITOR = config.othrys.system.defaultEditor;
    VISUAL = config.othrys.system.defaultEditor;
  };
}
