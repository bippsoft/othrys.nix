# modules/hardware/tablet.nix
# Pen tablets through OpenTabletDriver, for drawing and for games such as osu!
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.hardware.tablet;
in {
  # ANCHOR: tablet-options
  options.othrys.hardware.tablet = {
    enable = lib.mkEnableOption "pen tablet support through OpenTabletDriver";
  };
  # ANCHOR_END: tablet-options

  config = lib.mkIf cfg.enable {
    # Installs the driver and its configuration GUI system-wide, and runs the
    # daemon as a user unit in each graphical session.
    hardware.opentabletdriver = {
      enable = true;
      daemon.enable = true;
    };

    # The .NET daemon exits with 143 when systemd stops it with SIGTERM, which
    # the upstream unit counts as a failure, so every logout left the unit
    # marked failed.
    systemd.user.services.opentabletdriver.serviceConfig.SuccessExitStatus = 143;

    # The tablet area, bindings and filters the GUI writes.
    othrys.internal.persist."hardware.tablet" = {
      user.directories = [".config/OpenTabletDriver"];
    };
  };
}
