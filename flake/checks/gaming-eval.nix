# flake/checks/gaming-eval.nix
# CORE. What the GameMode and Steam modules grant the user, read back from
# evaluated hosts. A user outside the gamemode group and a device nobody can
# open both evaluate cleanly, and each leaves games on the slower path
# without an error anyone sees.
{
  hostConfig,
  mkExpectations,
  bootBase,
  functioningHost,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;

  gaming = extra:
    hostConfig [
      functioningHost
      {
        othrys.system.nix.allowUnfree = true;
        othrys.apps.gaming = {
          gamemode.enable = true;
          steam.enable = true;
        };
      }
      extra
    ];

  managed = gaming {};
  noNtsync = gaming {othrys.apps.gaming.steam.ntsync = false;};

  # GameMode on a host whose account othrys does not manage.
  anonymous = hostConfig [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
      othrys.apps.gaming.gamemode.enable = true;
    }
  ];

  groupsOf = cfg: cfg.users.users.alice.extraGroups;
  general = cfg: cfg.programs.gamemode.settings.general;
in
  mkExpectations "othrys-eval-gaming" {
    "the primary user is in the gamemode group" = builtins.elem "gamemode" (groupsOf managed);
    "the user keeps wheel beside gamemode" = builtins.elem "wheel" (groupsOf managed);
    "an unmanaged host gets no user account from GameMode" = !(anonymous.users.users ? alice);
    "renice is written and the wrapper can apply it" =
      (general managed).renice == 15 && managed.programs.gamemode.enableRenice;
    "softrealtime is left to gamemode's own default" = !((general managed) ? softrealtime);
    "the GPU settings are still accepted" =
      managed.programs.gamemode.settings.gpu.apply_gpu_optimisations == "accept-responsibility";

    "Steam loads ntsync on a kernel that ships it" = builtins.elem "ntsync" managed.boot.kernelModules;
    "the active seat's user can open /dev/ntsync" =
      lib.hasInfix ''KERNEL=="ntsync", MODE="0660", TAG+="uaccess"'' managed.services.udev.extraRules;
    "ntsync off loads nothing and writes no rule" =
      !(builtins.elem "ntsync" noNtsync.boot.kernelModules)
      && !(lib.hasInfix "ntsync" noNtsync.services.udev.extraRules);
  }
