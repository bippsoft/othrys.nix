# flake/checks/shell-eval.nix
# CORE. The shell layer, read back from evaluated hosts. A headless host
# once warned on every rebuild that Home Manager configuration was skipped,
# because two modules wrote registry entries whether or not the host had a
# managed user. Enabling zsh left bash as the login shell, and EDITOR was
# exported by both shells and by the editor module.
{
  hostConfig,
  mkExpectations,
  bootBase,
  functioningHost,
}: let
  headless = hostConfig [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
    }
  ];
  zshHost = hostConfig [
    functioningHost
    {othrys.system.shell.zsh.enable = true;}
  ];
  nvimHost = hostConfig [
    functioningHost
    {
      othrys.system.shell.zsh.enable = true;
      othrys.apps.nixvim.enable = true;
    }
  ];
  user = h: h.users.users.${h.othrys.system.user.name};
  hm = h: h.home-manager.users.${h.othrys.system.user.name};
  skipped = h: builtins.any (w: builtins.match ".*home-manager configuration was.*skipped.*" w != null) h.warnings;
  aliases = h: (hm h).programs.zsh.shellAliases;
in
  mkExpectations "othrys-eval-shell" {
    "a headless host does not warn about skipped home-manager configuration" = !skipped headless;
    "a functioning host has no skipped warning either" = !skipped zshHost;
    "enabling zsh makes it the login shell" = (user zshHost).shell == zshHost.programs.zsh.package || (user zshHost).shell.pname or "" == "zsh";
    "EDITOR and VISUAL follow defaultEditor through environment.variables" = zshHost.environment.variables.EDITOR == "vim" && zshHost.environment.variables.VISUAL == "vim";
    "nixvim makes itself the default editor" = nvimHost.environment.variables.EDITOR == "nvim";
    "nixvim does not export EDITOR a second time" = !((hm nvimHost).home.sessionVariables ? EDITOR);
    "hm-switch is gone" = !(aliases zshHost ? hm-switch);
    "nix-clean keeps generations" = builtins.match ".*--delete-older-than.*" (aliases zshHost).nix-clean != null;
    "fzf lists files with the installed fd" = builtins.match "/nix/store/.*/bin/fd .*" (hm zshHost).programs.fzf.defaultCommand != null && builtins.any (p: p.pname or "" == "fd") (hm zshHost).home.packages;
  }
