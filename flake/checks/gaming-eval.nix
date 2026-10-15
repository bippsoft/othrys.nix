# flake/checks/gaming-eval.nix
# CORE. What the GameMode, Steam and ntsync modules grant the user, read
# back from evaluated hosts. A user outside the gamemode group and a device
# nobody can open both evaluate cleanly, and each leaves games on the slower
# path without an error anyone sees.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
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
  noNtsync = gaming {othrys.hardware.ntsync.enable = false;};
  renamedNtsync = gaming {othrys.apps.gaming.steam.ntsync = false;};

  # A kernel older than ntsync, forced over whatever the fixture picks.
  oldKernel = {pkgs, ...}: {boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_6_12;};
  steamOldKernel = gaming oldKernel;

  # ntsync for a Wine runner, with no Steam on the host.
  ntsyncOnly = extra:
    hostConfig [
      functioningHost
      {othrys.hardware.ntsync.enable = true;}
      extra
    ];
  wineHost = ntsyncOnly {};
  ntsyncOldKernel = ntsyncOnly oldKernel;

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

    "Steam turns ntsync on by default on a kernel that ships it" =
      managed.othrys.hardware.ntsync.enable && builtins.elem "ntsync" managed.boot.kernelModules;
    "the active seat's user can open /dev/ntsync" =
      lib.hasInfix ''KERNEL=="ntsync", MODE="0660", TAG+="uaccess"'' managed.services.udev.extraRules;
    "ntsync off loads nothing and writes no rule" =
      !(builtins.elem "ntsync" noNtsync.boot.kernelModules)
      && !(lib.hasInfix "ntsync" noNtsync.services.udev.extraRules);
    "a host without Steam loads ntsync and gets the rule" =
      !wineHost.othrys.apps.gaming.steam.enable
      && builtins.elem "ntsync" wineHost.boot.kernelModules
      && lib.hasInfix ''KERNEL=="ntsync"'' wineHost.services.udev.extraRules;
    "the old Steam option still turns ntsync off, with a rename warning" =
      !renamedNtsync.othrys.hardware.ntsync.enable
      && !(builtins.elem "ntsync" renamedNtsync.boot.kernelModules)
      && builtins.any (lib.hasInfix "othrys.hardware.ntsync.enable") renamedNtsync.warnings;
    "Steam on a kernel before 6.14 leaves ntsync off" =
      !steamOldKernel.othrys.hardware.ntsync.enable && !rejectedWith "othrys.hardware.ntsync" steamOldKernel;
    "ntsync on a kernel before 6.14 is rejected" = rejectedWith "ships with kernel 6.14" ntsyncOldKernel;
  }
