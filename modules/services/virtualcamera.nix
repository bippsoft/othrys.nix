# modules/services/virtualcamera.nix
# Virtual camera via v4l2loopback kernel module
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.services.virtualcamera;
in {
  options.othrys.services.virtualcamera = {
    enable = lib.mkEnableOption "Virtual camera (v4l2loopback)";

    videoNr = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Video device number for the virtual camera.";
    };

    cardLabel = lib.mkOption {
      type = lib.types.str;
      default = "Virtual Camera";
      description = "Label for the virtual camera device.";
    };

    devices = lib.mkOption {
      type = lib.types.int;
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
      options v4l2loopback devices=${toString cfg.devices} video_nr=${toString cfg.videoNr} card_label="${cfg.cardLabel}" exclusive_caps=1
    '';
  };
}
