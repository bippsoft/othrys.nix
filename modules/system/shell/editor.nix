# modules/system/shell/editor.nix
# The default editor option, shared by the shell and git modules
{lib, ...}: {
  options.othrys.system.defaultEditor = lib.mkOption {
    type = lib.types.str;
    # vim ships in the essential package set (system/users.nixos.nix), and anything
    # fancier is the consumer's choice.
    default = "vim";
    description = "Default editor, used for EDITOR/VISUAL and git's core.editor. An editor module that wants to be the default sets it with mkDefault.";
  };
}
