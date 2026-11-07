# modules/system/shell/zsh.nixos.nix
# The NixOS implementation of othrys.system.shell.zsh
{
  config,
  lib,
  pkgs,
  ...
}: let
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.system.shell.zsh;
in {
  imports = [./zsh.nix];

  config = lib.mkIf cfg.enable {
    # The history file is persisted through its directory rather than on its
    # own. zsh saves history by writing a temporary file and renaming it over
    # HISTFILE, and a rename onto a bind-mounted file fails, so a persisted
    # file would never take a save. The direnv allow database belongs to the
    # development module, which owns direnv.
    othrys.internal.persist."system.shell.zsh" = {
      user = {
        directories = [
          ".local/share/zoxide"
          ".local/share/zsh"
        ];
        files = lib.optionals cfg.persistCompdump [".zcompdump"];
      };
    };

    programs.zsh.enable = true;

    # Enabling the shell makes it the primary user's login shell. The option
    # is read only when the account exists, and a host that wants another
    # shell states it.
    othrys.system.users.defaultShell = lib.mkIf usersEnabled (lib.mkDefault pkgs.zsh);
  };
}
