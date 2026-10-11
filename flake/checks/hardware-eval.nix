# flake/checks/hardware-eval.nix
# CORE. What the hardware, mount and disk modules write, read back from
# evaluated hosts. A scanner without mDNS, a notify command that cannot read
# its token, a mount without ownership and a discard that nothing issues all
# evaluate cleanly, so the settings themselves are compared here.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;

  nix = {
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
  };

  # disko asserts nothing here, and enableConfig = false keeps it from emitting
  # filesystems that collide with the fixture's own root.
  disko = settings: {
    disko.enableConfig = false;
    othrys.system.disko = {enable = true;} // settings;
  };

  equipped = hostConfig [
    functioningHost
    (disko {device = "/dev/disk/by-id/example";})
    {
      othrys.hardware = {
        scanner.enable = true;
        webcam.enable = true;
        wireless.bluetooth.enable = true;
        wireless.wifi = {
          enable = true;
          networks."guest-5g.lan".ssid = "example";
        };
        ups = {
          enable = true;
          passwordFile = "/run/secrets/ups";
        };
      };
      othrys.services = {
        notify = {
          enable = true;
          url = "https://ntfy.example.com";
          tokenFile = "/run/secrets/ntfy";
        };
        virtualcamera = {
          enable = true;
          devices = 2;
        };
        mounts.disks = {
          enable = true;
          devices.usb = {
            device = "/dev/disk/by-label/usb";
            mountPoint = "/mnt/usb";
            fsType = "vfat";
          };
        };
        mounts.cifs = {
          enable = true;
          shares.media = {
            remotePath = "//nas.example.com/media";
            credentialsFile = "/run/secrets/cifs";
          };
        };
      };
    }
  ];

  bareDevice = hostConfig [
    bootBase
    nix
    (disko {
      device = "/dev/sda";
      luks.allowDiscards = false;
    })
  ];

  primeAlone = hostConfig [bootBase nix {othrys.hardware.nvidia.prime.enable = true;}];
  primeSet = hostConfig [
    functioningHost
    {
      othrys.system.nix.allowUnfree = true;
      othrys.hardware.nvidia = {
        enable = true;
        prime = {
          enable = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
        };
      };
    }
  ];

  upsmon = equipped.systemd.services.upsmon;
  mountOptions = cfg: mountPoint: cfg.fileSystems.${mountPoint}.options;
  hasAll = wanted: have: builtins.all (o: builtins.elem o have) wanted;
  deviceWarning = cfg: builtins.any (lib.hasInfix "othrys.system.disko.device") cfg.warnings;
in
  mkExpectations "othrys-eval-hardware" {
    "the scanner turns avahi on" = equipped.services.avahi.enable && equipped.services.avahi.nssmdns4;
    "upsmon loads the ntfy token as a credential" = builtins.elem "token:/run/secrets/ntfy" upsmon.serviceConfig.LoadCredential;
    "upsmon keeps the password credential beside it" = builtins.length upsmon.serviceConfig.LoadCredential == 2;
    "the token is staged before upsmon starts" = builtins.length (lib.toList upsmon.serviceConfig.ExecStartPre) == 2;
    "othrys-notify is on the upsmon PATH" = builtins.elem "/run/current-system/sw" upsmon.path;
    "the webcam adds no video group" = !builtins.elem "video" equipped.users.users.alice.extraGroups;
    "the bluetooth main.conf has no Enable key" = !(equipped.hardware.bluetooth.settings.General ? Enable);
    "a network name is sanitised into its passphrase variable" = equipped.networking.networkmanager.ensureProfiles.profiles."guest-5g.lan".wifi-security.psk == "$WIFI_PSK_GUEST_5G_LAN";
    "each virtual camera gets its own number and label" = lib.hasInfix ''devices=2 video_nr=10,11 card_label="Virtual Camera,Virtual Camera 2" exclusive_caps=1,1'' equipped.boot.extraModprobeConfig;
    "a vfat mount is owned and takes nosuid and nodev" = hasAll ["uid=1000" "gid=100" "dmask=022" "fmask=133" "nosuid" "nodev"] (mountOptions equipped "/mnt/usb");
    "a cifs mount pins the dialect, seals and takes nosuid and nodev" = hasAll ["vers=3.1.1" "seal" "sec=ntlmssp" "nosuid" "nodev"] (mountOptions equipped "/mnt/shares/media");
    "fstrim follows allowDiscards on" = equipped.services.fstrim.enable;
    "fstrim follows allowDiscards off" = !bareDevice.services.fstrim.enable;
    "a device under /dev/disk raises no warning" = !deviceWarning equipped;
    "a bare device name raises the warning" = deviceWarning bareDevice;
    "PRIME without the driver is rejected" = rejectedWith "set othrys.hardware.nvidia.enable" primeAlone;
    "PRIME without bus ids is rejected" = rejectedWith "set intelBusId and nvidiaBusId" primeAlone;
    "PRIME with the driver and bus ids is accepted" = !rejectedWith "othrys.hardware.nvidia.prime" primeSet;
    "the bus ids reach the driver" = primeSet.hardware.nvidia.prime.intelBusId == "PCI:0:2:0" && primeSet.hardware.nvidia.prime.nvidiaBusId == "PCI:1:0:0";
    "PRIME adds no kernel parameter of its own" = !builtins.any (p: lib.hasPrefix "nvidia" p || lib.hasPrefix "i915" p) primeSet.boot.kernelParams;
    "nixpkgs still turns modesetting on through the module parameters" = primeSet.hardware.nvidia.moduleParams.nvidia-drm.modeset == 1;
    "video memory is preserved through the power management option" = primeSet.hardware.nvidia.powerManagement.enable && primeSet.hardware.nvidia.moduleParams.nvidia.NVreg_PreserveVideoMemoryAllocations == 1;
    "i915 is not blacklisted unless asked" = !builtins.elem "i915" primeSet.boot.blacklistedKernelModules;
  }
