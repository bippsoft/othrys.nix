# modules/hardware/scanner.nix
# Scanner support through SANE, with network scanners discovered over mDNS
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.hardware.scanner;
in {
  # ANCHOR: scanner-options
  options.othrys.hardware.scanner = {
    enable = lib.mkEnableOption "scanner support (SANE + network scanner discovery)";

    extraBackends = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "[pkgs.hplipWithPlugin]";
      description = "Additional SANE backends (vendor drivers) beyond the airscan default.";
    };
  };
  # ANCHOR_END: scanner-options

  config = lib.mkIf cfg.enable {
    hardware.sane = {
      enable = true;
      extraBackends = [pkgs.sane-airscan] ++ cfg.extraBackends;
    };

    # sane-airscan finds eSCL and WSD scanners by browsing mDNS through
    # avahi-daemon, and without the daemon it lists only the devices named by
    # hand in airscan.conf. mkDefault leaves a host free to turn discovery off
    # and keep the static entries.
    services.avahi = {
      enable = lib.mkDefault true;
      nssmdns4 = lib.mkDefault true;
    };

    # Group membership only when othrys manages the user account (writing
    # users.users.<name> otherwise materializes a phantom user).
    users.users = lib.mkIf usersEnabled {
      ${username}.extraGroups = ["scanner" "lp"];
    };

    # GUI frontend only on graphical hosts, and scanimage covers headless use.
    environment.systemPackages = lib.optionals config.othrys.desktop.graphical [
      pkgs.simple-scan
    ];
  };
}
