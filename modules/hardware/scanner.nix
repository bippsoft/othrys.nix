# modules/hardware/scanner.nix
# Scanner support through SANE with network-scanner discovery (sane-airscan covers
# most modern eSCL/WSD devices). The GUI frontend follows the graphical
# signal, and headless scan servers use scanimage/scanadf.
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
