# modules/system/kernel.nix
# Linux kernel selection
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.kernel;
in {
  options.othrys.system.kernel = {
    enable = lib.mkEnableOption "kernel package selection (disabled = NixOS default kernel)";

    package = lib.mkOption {
      type = lib.types.raw;
      default = pkgs.linuxPackages_latest;
      # Rendering the raw kernel-packages set forces every attr in it
      # (including removed/broken ones), so the docs need the symbolic form.
      defaultText = lib.literalExpression "pkgs.linuxPackages_latest";
      description = "Kernel package set to use (e.g., pkgs.linuxPackages_latest, pkgs.linuxPackages_lts).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = lib.mkDefault cfg.package;
  };
}
