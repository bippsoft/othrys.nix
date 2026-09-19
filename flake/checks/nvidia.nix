# flake/checks/nvidia.nix
# CORE. Which NVIDIA driver and which kernel modules a host ends up with, read
# back from the evaluated host. A card the stable driver has dropped needs an
# older branch and the proprietary modules, and nothing at evaluation can tell
# which card a host has, so the option is the only thing to check.
{
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  host = nvidia:
    hostConfig [
      functioningHost
      ({config, ...}: {
        othrys.system.nix.allowUnfree = true;
        othrys.hardware.nvidia = {enable = true;} // nvidia config;
      })
    ];

  plain = host (_: {});
  pascal = host (config: {
    openModules = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
  });

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
  }
