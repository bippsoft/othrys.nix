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
  diskoModules,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;

  nix = {
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
  };

  # The disk layout with the disko module it writes into. disko asserts
  # nothing here, and enableConfig = false keeps it from emitting filesystems
  # that collide with the fixture's own root.
  disko = settings: {
    imports = [diskoModules];
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
          devices.windows = {
            device = "/dev/disk/by-label/windows";
            mountPoint = "/mnt/windows";
            fsType = "ntfs-3g";
          };
          devices.shared = {
            device = "/dev/disk/by-label/shared";
            mountPoint = "/mnt/shared";
            fsType = "ntfs3";
          };
          devices.data = {
            device = "/dev/disk/by-label/data";
            mountPoint = "/mnt/data";
            fsType = "ext4";
          };
          devices.containers = {
            device = "/dev/disk/by-label/containers";
            mountPoint = "/mnt/containers";
            fsType = "ext4";
            allowSuid = true;
            allowDev = true;
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

  # A share on a host that names a user and manages no account, with and
  # without an owner of its own.
  share = settings:
    hostConfig [
      bootBase
      nix
      {
        othrys.services.mounts.cifs = {
          enable = true;
          shares.media =
            {
              remotePath = "//nas.example.com/media";
              credentialsFile = "/run/secrets/cifs";
            }
            // settings;
        };
      }
    ];
  shareUnowned = share {};
  shareOwned = share {
    uid = 1500;
    gid = "media";
  };
  ownerNeedle = "uid and gid default to the primary account";

  # A type refuses a value while the option is being read, which aborts the
  # evaluation, so the mask is read under tryEval.
  masked = dmask:
    builtins.tryEval
    (hostConfig [
      bootBase
      nix
      {
        othrys.services.mounts.disks = {
          enable = true;
          devices.usb = {
            device = "/dev/disk/by-label/usb";
            mountPoint = "/mnt/usb";
            fsType = "vfat";
            inherit dmask;
          };
        };
      }
    ]).othrys.services.mounts.disks.devices.usb.dmask;

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

  cpu = vendor: hostConfig [bootBase nix {othrys.hardware.cpu.vendor = vendor;}];
  intel = cpu "intel";
  amd = cpu "amd";
  noCpu = hostConfig [bootBase nix];
  powerspec = hostConfig [bootBase nix {othrys.hardware.laptop.powerspec-1710.enable = true;}];
  cpuRefused = (builtins.tryEval (cpu "arm").othrys.hardware.cpu.vendor).success;

  tablet = hostConfig [functioningHost {othrys.hardware.tablet.enable = true;}];
  osu = extra:
    hostConfig [
      functioningHost
      {
        othrys.system.nix.allowUnfree = true;
        othrys.apps.gaming.osu.enable = true;
      }
      extra
    ];
  osuDefault = osu {};
  osuNoTablet = osu {othrys.apps.gaming.osu.enableTabletDriver = false;};
  hasPackage = cfg: name: builtins.any (p: (p.pname or "") == name) cfg.environment.systemPackages;

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
    "an ntfs-3g mount takes nosuid and nodev" = hasAll ["nosuid" "nodev" "big_writes"] (mountOptions equipped "/mnt/windows");
    "an ntfs3 mount takes nosuid and nodev" = hasAll ["nosuid" "nodev" "windows_names"] (mountOptions equipped "/mnt/shared");
    "an ext4 mount takes nosuid and nodev" = hasAll ["nosuid" "nodev"] (mountOptions equipped "/mnt/data");
    "allowSuid and allowDev drop both options" = !builtins.elem "nosuid" (mountOptions equipped "/mnt/containers") && !builtins.elem "nodev" (mountOptions equipped "/mnt/containers");
    "an octal mask of three or four digits is accepted" = (masked "027").success && (masked "0077").success;
    "a mask that is not octal is refused" = !(masked "0x22").success && !(masked "rwx").success && !(masked "89").success;
    "a cifs share belongs to the primary user and group by default" = hasAll ["uid=alice" "gid=users"] (mountOptions equipped "/mnt/shares/media");
    "a cifs share without an owner on a host with no account is rejected" = rejectedWith ownerNeedle shareUnowned;
    "a cifs share with its own owner is accepted there" = !rejectedWith ownerNeedle shareOwned && hasAll ["uid=1500" "gid=media"] (mountOptions shareOwned "/mnt/shares/media");
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

    "an Intel CPU gets microcode, firmware and kvm-intel" =
      intel.hardware.cpu.intel.updateMicrocode
      && intel.hardware.enableRedistributableFirmware
      && builtins.elem "kvm-intel" intel.boot.kernelModules
      && !intel.hardware.cpu.amd.updateMicrocode;
    "an AMD CPU gets microcode, firmware and kvm-amd" =
      amd.hardware.cpu.amd.updateMicrocode
      && amd.hardware.enableRedistributableFirmware
      && builtins.elem "kvm-amd" amd.boot.kernelModules
      && !amd.hardware.cpu.intel.updateMicrocode;
    "no vendor writes no microcode, firmware or KVM module" =
      !noCpu.hardware.cpu.intel.updateMicrocode
      && !noCpu.hardware.cpu.amd.updateMicrocode
      && !noCpu.hardware.enableRedistributableFirmware
      && !builtins.any (m: lib.hasPrefix "kvm-" m) noCpu.boot.kernelModules;
    "a vendor outside intel and amd is refused" = !cpuRefused;
    "the tablet module runs the OpenTabletDriver daemon and installs its GUI" =
      tablet.hardware.opentabletdriver.enable
      && tablet.hardware.opentabletdriver.daemon.enable
      && hasPackage tablet "OpenTabletDriver";
    "a SIGTERM stop of the tablet daemon counts as success" =
      tablet.systemd.user.services.opentabletdriver.serviceConfig.SuccessExitStatus == 143;
    "the tablet settings are persisted" =
      tablet.othrys.internal.persist."hardware.tablet".user.directories == [".config/OpenTabletDriver"];
    "a tablet host gets no osu!" = !tablet.othrys.apps.gaming.osu.enable;
    "osu! turns the tablet on by default" = osuDefault.othrys.hardware.tablet.enable;
    "the old osu! option still turns the tablet off, with a rename warning" =
      !osuNoTablet.othrys.hardware.tablet.enable
      && !osuNoTablet.hardware.opentabletdriver.enable
      && builtins.any (lib.hasInfix "othrys.hardware.tablet.enable") osuNoTablet.warnings;
    "the PowerSpec 1710 states an Intel CPU" =
      powerspec.othrys.hardware.cpu.vendor
      == "intel"
      && powerspec.hardware.cpu.intel.updateMicrocode;
  }
