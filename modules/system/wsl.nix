# modules/system/wsl.nix
# A host that runs as a NixOS-WSL distro on Windows
#
# WSL starts the distro inside a Windows-owned kernel and hands it its disk,
# its network and its DNS. NixOS-WSL turns off the initrd, the kernel and the
# bootloader to match, and the options here choose the parts of it a host
# varies: the account WSL logs in as, whether the Windows PATH reaches the
# shell, and which USB devices usbipd-win attaches.
#
# Exported as nixosModules.wsl and left out of nixosModules.default and
# nixosModules.full, so a host imports it together with the NixOS-WSL module
# or imports neither. It is the only file in this tree that writes into the
# `wsl` option namespace.
#
# Five othrys modules configure what WSL owns, and a host that enables one
# beside this module is refused. disko is an optional export, so its enable
# flag is read only on a host that declares it.
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.wsl;

  conflicting = {
    "othrys.system.bootloader.enable" = config.othrys.system.bootloader.enable;
    "othrys.system.disko.enable" = lib.attrByPath ["othrys" "system" "disko" "enable"] false config;
    "othrys.system.impermanence.enable" = config.othrys.system.impermanence.enable;
    "othrys.system.kernel.enable" = config.othrys.system.kernel.enable;
    "othrys.system.networking.enable" = config.othrys.system.networking.enable;
  };
in {
  # ANCHOR: wsl-options
  options.othrys.system.wsl = {
    enable = lib.mkEnableOption "running the host as a NixOS-WSL distro";

    defaultUser = lib.mkOption {
      type = lib.types.str;
      default = config.othrys.system.user.name;
      defaultText = lib.literalExpression "config.othrys.system.user.name";
      description = "The account WSL logs in as when the distro starts, written to `wsl.defaultUser`.";
    };

    windowsPath = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Append the Windows PATH to the PATH of the distro. Off by default, so
        a name such as `git` or `node` resolves to the Nix package and not to
        a Windows binary of the same name. Interop stays on either way, and a
        Windows binary still runs by its full path, as in
        `/mnt/c/Windows/explorer.exe`.
      '';
    };

    usbip = {
      enable = lib.mkEnableOption "attaching Windows USB devices through usbipd-win";

      autoAttach = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["4-1"];
        description = ''
          Bus IDs to attach at boot, as `usbipd list` prints them on Windows.
          Each device has to be bound once on Windows with
          `usbipd bind --busid <id>`.
        '';
      };

      hostAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "127.0.0.1";
        description = ''
          The address of the Windows host that runs usbipd-win. null keeps the
          NixOS-WSL default, which reads the gateway of `eth0`. Under
          `networkingMode=mirrored` the distro has no such route, so a
          mirrored host sets `127.0.0.1`.
        '';
      };
    };

    startMenuLaunchers = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Add a Windows Start menu shortcut for each GUI application the host installs.";
    };
  };
  # ANCHOR_END: wsl-options

  config = lib.mkIf cfg.enable {
    assertions =
      lib.mapAttrsToList (name: on: {
        assertion = !on;
        message = "othrys.system.wsl.enable is set together with ${name}. WSL owns the kernel, the boot, the disk and the network of the distro, so a WSL host leaves that module off.";
      })
      conflicting;

    wsl = {
      enable = true;
      inherit (cfg) defaultUser startMenuLaunchers;
      interop.includePath = cfg.windowsPath;
      wslConf.interop.appendWindowsPath = cfg.windowsPath;
      usbip =
        {
          inherit (cfg.usbip) enable autoAttach;
        }
        // lib.optionalAttrs (cfg.usbip.hostAddress != null) {
          snippetIpAddress = cfg.usbip.hostAddress;
        };
    };
  };
}
