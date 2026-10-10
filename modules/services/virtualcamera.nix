# modules/services/virtualcamera.nix
# Virtual camera via v4l2loopback kernel module
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.virtualcamera;

  # v4l2loopback takes video_nr, card_label and exclusive_caps as
  # comma-separated arrays with one entry per device. A single entry beside
  # devices=2 applies to the first device and leaves the second to the
  # kernel's own numbering and defaults.
  indices = lib.range 0 (cfg.devices - 1);
  videoNrs = map (i: toString (cfg.videoNr + i)) indices;
  cardLabels = map (i:
    if i == 0
    then cfg.cardLabel
    else "${cfg.cardLabel} ${toString (i + 1)}")
  indices;
in {
  options.othrys.services.virtualcamera = {
    enable = lib.mkEnableOption "Virtual camera (v4l2loopback)";

    videoNr = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 10;
      description = "Video device number of the first virtual camera, which appears as /dev/video<n>. Each further device takes the next number.";
    };

    cardLabel = lib.mkOption {
      # The kernel reads the value between one pair of double quotes and
      # splits it on commas, and modprobe.d has no escape for either. A quote
      # would end the value early and a comma would start another label, so
      # the type refuses them.
      type = lib.types.strMatching "[A-Za-z0-9 _.-]+";
      default = "Virtual Camera";
      description = "Label of the virtual camera device. Letters, digits, spaces, `_`, `.` and `-` only. Each further device carries the label followed by its number.";
    };

    devices = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of virtual camera devices to create.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [
      config.boot.kernelPackages.v4l2loopback
    ];

    boot.kernelModules = ["v4l2loopback"];

    boot.extraModprobeConfig = ''
      options v4l2loopback devices=${toString cfg.devices} video_nr=${lib.concatStringsSep "," videoNrs} card_label="${lib.concatStringsSep "," cardLabels}" exclusive_caps=${lib.concatMapStringsSep "," (_: "1") indices}
    '';
  };
}
