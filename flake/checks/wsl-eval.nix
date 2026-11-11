# flake/checks/wsl-eval.nix
# CORE. What the WSL adapter hands NixOS-WSL, read back from evaluated hosts.
# The login account, the Windows PATH switches and the usbip settings are
# strings and lists in wsl.conf and in systemd wants, and none of them fails
# evaluation when it is wrong. The host is built to its top level and to the
# tarball builder a first install runs, since NixOS-WSL turns off the
# kernel, the initrd and the bootloader, and a module that still writes one
# fails only there.
{
  inputs,
  hostEval,
  mkExpectations,
  rejectedWith,
  wslModules,
  diskoModules,
  impermanenceModules,
}: let
  inherit (inputs.nixpkgs) lib;

  nix = {
    othrys.system.user.name = "alice";
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
  };
  wslWith = settings: hostEval [wslModules nix {othrys.system.wsl = {enable = true;} // settings;}];
  wslConfig = settings: (wslWith settings).config;
  beside = extra: (hostEval ([wslModules nix {othrys.system.wsl.enable = true;}] ++ extra)).config;

  plain = wslWith {};
  host = plain.config;
  otherUser = wslConfig {defaultUser = "bob";};
  windowsPath = wslConfig {windowsPath = true;};
  usbip = wslConfig {
    usbip = {
      enable = true;
      autoAttach = ["4-1" "2-3"];
    };
  };
  mirrored = wslConfig {
    usbip = {
      enable = true;
      hostAddress = "127.0.0.1";
    };
  };
  off = (hostEval [wslModules nix]).config;
  defaultAlone = (hostEval [nix]).config;

  wants = h: h.systemd.targets.multi-user.wants or [];
  refusedByWsl = h: builtins.any (a: !a.assertion && lib.hasInfix "othrys.system.wsl" a.message) h.assertions;
  refusedBeside = name: h: rejectedWith "othrys.system.wsl.enable is set together with ${name}" h;
in
  mkExpectations "othrys-eval-wsl" {
    "a WSL host evaluates to its top level" = host.system.build.toplevel.drvPath != null;
    "a WSL host evaluates its tarball builder" = host.system.build.tarballBuilder.drvPath != null;
    "a WSL host passes every wsl assertion" = !(refusedByWsl host);

    "the adapter turns NixOS-WSL on" = host.wsl.enable;
    "WSL logs in as the primary user" = host.wsl.defaultUser == "alice";
    "a host's own login account reaches NixOS-WSL" = otherUser.wsl.defaultUser == "bob";

    "the Windows PATH stays out of the shell by default" = !host.wsl.interop.includePath;
    "wsl.conf does not append the Windows PATH by default" = !host.wsl.wslConf.interop.appendWindowsPath;
    "interop stays on when the Windows PATH is off" = host.wsl.wslConf.interop.enabled;
    "windowsPath turns both PATH switches on" = windowsPath.wsl.interop.includePath && windowsPath.wsl.wslConf.interop.appendWindowsPath;

    "usbip is off by default" = !host.wsl.usbip.enable;
    "usbip attaches each listed bus ID at boot" =
      builtins.all (id: builtins.elem "usbip-auto-attach@${id}.service" (wants usbip)) ["4-1" "2-3"];
    "usbip keeps the NixOS-WSL address snippet when hostAddress is null" =
      usbip.wsl.usbip.snippetIpAddress == plain.options.wsl.usbip.snippetIpAddress.default;
    "hostAddress reaches the usbip snippet" = mirrored.wsl.usbip.snippetIpAddress == "127.0.0.1";

    "WSL beside the bootloader module is refused" =
      refusedBeside "othrys.system.bootloader.enable" (beside [{othrys.system.bootloader.enable = true;}]);
    "WSL beside the kernel module is refused" =
      refusedBeside "othrys.system.kernel.enable" (beside [{othrys.system.kernel.enable = true;}]);
    "WSL beside the networking module is refused" =
      refusedBeside "othrys.system.networking.enable" (beside [{othrys.system.networking.enable = true;}]);
    "WSL beside impermanence is refused" = refusedBeside "othrys.system.impermanence.enable" (beside [
      impermanenceModules
      {othrys.system.impermanence.enable = true;}
    ]);
    "WSL beside the disko layout is refused" = refusedBeside "othrys.system.disko.enable" (beside [
      diskoModules
      {
        othrys.system.disko = {
          enable = true;
          device = "/dev/disk/by-id/nvme-EXAMPLE";
        };
      }
    ]);

    "a host with the adapter and WSL off leaves NixOS-WSL off" = !off.wsl.enable;
    "a host built from default alone declares no wsl option" = !(defaultAlone ? wsl);
  }
