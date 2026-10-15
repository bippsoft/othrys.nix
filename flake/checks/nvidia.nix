# flake/checks/nvidia.nix
# CORE. Which NVIDIA driver and which kernel modules a host ends up with, read
# back from the evaluated host. A card the stable driver has dropped needs an
# older branch and the proprietary modules, and nothing at evaluation can tell
# which card a host has, so the option is the only thing to check. The initrd
# module list is read back as well, since it decides the size of every initrd.
# The container toolkit belongs to the driver and not to one container
# runtime, so it is read on a Podman host and on a rootless Docker host.
{
  hostConfig,
  mkExpectations,
  functioningHost,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;

  hostWith = extra: nvidia:
    hostConfig [
      functioningHost
      ({config, ...}: {
        othrys.system.nix.allowUnfree = true;
        othrys.hardware.nvidia = {enable = true;} // nvidia config;
      })
      extra
    ];
  host = hostWith {};

  toolkit = {containerToolkit.enable = true;};
  podmanToolkit = hostWith {othrys.services.containerization.podman.enable = true;} (_: toolkit);
  rootlessDockerToolkit = hostWith {othrys.services.containerization.docker.enable = true;} (_: toolkit);
  renamedToolkit = hostWith {
    othrys.services.containerization.docker = {
      enable = true;
      nvidia.enable = true;
    };
  } (_: {});

  plain = host (_: {});
  pascal = host (config: {
    openModules = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  });

  primeSettings = {
    enable = true;
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
  prime = host (_: {prime = primeSettings;});
  primeEarly = host (_: {
    prime = primeSettings;
    earlyLoad = true;
  });

  nvidiaModules = ["nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"];
  hasAll = wanted: have: builtins.all (m: builtins.elem m have) wanted;
  hasNone = unwanted: have: !builtins.any (m: builtins.elem m have) unwanted;

  branch = cfg: builtins.head (builtins.splitVersion cfg.hardware.nvidia.package.version);
  noFailedAssertion = cfg: builtins.all (a: a.assertion) cfg.assertions;
in
  mkExpectations "othrys-eval-nvidia" {
    "a host that sets nothing gets the stable driver" =
      plain.hardware.nvidia.package.version == plain.boot.kernelPackages.nvidiaPackages.stable.version;
    "a host that sets nothing gets the open modules" = plain.hardware.nvidia.open;
    "the default host passes every assertion" = noFailedAssertion plain;
    "a host can choose the 580 branch" = branch pascal == "580";
    "the chosen driver is built for the host's own kernel" =
      pascal.hardware.nvidia.package.version == pascal.boot.kernelPackages.nvidiaPackages.legacy_580.version;
    "openModules = false reaches hardware.nvidia.open" = !pascal.hardware.nvidia.open;
    "the 580 host passes every assertion" = noFailedAssertion pascal;
    "a desktop loads the four NVIDIA modules in the initrd" = plain.othrys.hardware.nvidia.earlyLoad && hasAll nvidiaModules plain.boot.initrd.kernelModules;
    "a desktop keeps i915 out of the initrd" = !builtins.elem "i915" plain.boot.initrd.kernelModules;
    "a PRIME host defaults to loading the driver late" = !prime.othrys.hardware.nvidia.earlyLoad;
    "a PRIME host has i915 and no NVIDIA module in the initrd" = builtins.elem "i915" prime.boot.initrd.kernelModules && hasNone nvidiaModules prime.boot.initrd.kernelModules;
    "a PRIME host loads the four NVIDIA modules from the root filesystem" = hasAll nvidiaModules prime.boot.kernelModules;
    "a PRIME host with earlyLoad has all five modules in the initrd" = hasAll (nvidiaModules ++ ["i915"]) primeEarly.boot.initrd.kernelModules;
    "both PRIME hosts pass every assertion" = noFailedAssertion prime && noFailedAssertion primeEarly;

    "a host that sets nothing runs no container toolkit" = !plain.hardware.nvidia-container-toolkit.enable;
    "a Podman host gets the container toolkit without Docker" =
      podmanToolkit.hardware.nvidia-container-toolkit.enable
      && !podmanToolkit.othrys.services.containerization.docker.enable
      && noFailedAssertion podmanToolkit;
    "rootless Docker with the container toolkit is accepted and turns CDI on" =
      rootlessDockerToolkit.virtualisation.docker.rootless.enable
      && rootlessDockerToolkit.virtualisation.docker.rootless.daemon.settings.features.cdi
      && noFailedAssertion rootlessDockerToolkit;
    "the old Docker option still turns the toolkit on, with a rename warning" =
      renamedToolkit.othrys.hardware.nvidia.containerToolkit.enable
      && renamedToolkit.hardware.nvidia-container-toolkit.enable
      && builtins.any (lib.hasInfix "othrys.hardware.nvidia.containerToolkit.enable") renamedToolkit.warnings;
  }
