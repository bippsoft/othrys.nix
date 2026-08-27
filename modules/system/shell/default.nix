# modules/system/shell/default.nix
# Shell module aggregator
{lib, ...}: {
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
    description = "Default editor, used for EDITOR/VISUAL and git's core.editor.";
  };
}
