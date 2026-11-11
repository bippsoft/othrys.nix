# WSL

**Platforms:** NixOS only.

A host that runs as a [NixOS-WSL](https://github.com/nix-community/NixOS-WSL)
distro on Windows. WSL starts the distro inside a kernel Windows owns, and
hands it its disk, its network and its resolver. NixOS-WSL turns off the
kernel, the initrd and the bootloader to match.

## Importing

The adapter is the separate export `nixosModules.wsl`, which neither
`nixosModules.default` nor `nixosModules.full` imports. It is the only othrys
module that writes into the `wsl` option namespace, so a WSL host imports the
export together with the NixOS-WSL module:

```nix
# flake inputs
nixos-wsl.follows = "othrys/nixos-wsl";

# host modules
inputs.othrys.nixosModules.wsl
inputs.nixos-wsl.nixosModules.default
```

## Options

```nix
{{#include ../../../modules/system/wsl.nix:wsl-options}}
```

## Usage

```nix
othrys.system.wsl = {
  enable = true;
  usbip = {
    enable = true;
    autoAttach = ["4-1"];
    hostAddress = "127.0.0.1";
  };
};
```

WSL logs in as `othrys.system.user.name` unless `defaultUser` names another
account.

The Windows PATH stays out of the shell by default, so a name such as `git`
resolves to the Nix package. Interop stays on, and a Windows binary runs by its
full path under `/mnt/c`.

A USB device such as a YubiKey reaches the distro through
[usbipd-win](https://github.com/dorssel/usbipd-win). Each device is bound once
on Windows with `usbipd bind --busid <id>`, and its bus ID goes in
`usbip.autoAttach`. NixOS-WSL finds the Windows host from the gateway of
`eth0`, which a distro under `networkingMode=mirrored` does not have, so a
mirrored host sets `usbip.hostAddress = "127.0.0.1"`.

Five othrys modules configure what WSL owns, and a WSL host that enables one is
refused at evaluation. They are `othrys.system.bootloader`,
`othrys.system.disko`, `othrys.system.impermanence`, `othrys.system.kernel`
and `othrys.system.networking`.

## Installing

NixOS-WSL builds an importable tarball from the host's own configuration. On
a Linux machine with the consuming flake:

```bash
sudo nix run .#nixosConfigurations.<host>.config.system.build.tarballBuilder
```

The builder writes `nixos.wsl` to the working directory. On Windows, the
tarball is imported with `wsl --import <host> <directory> nixos.wsl`, or opened
directly where the installed WSL supports it.
