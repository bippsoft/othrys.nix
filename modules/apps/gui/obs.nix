# modules/apps/gui/obs.nix
# OBS Studio with its plugins and the loopback device its virtual camera writes to
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.obs;
  nvidiaEnabled = config.othrys.hardware.nvidia.enable;
in {
  options.othrys.apps.obs = {
    enable = lib.mkEnableOption "OBS Studio with virtual camera";
  };

  config = lib.mkIf cfg.enable {
    # Scenes, profiles and the stream service settings, which carry the stream
    # key in plaintext, so the directory is 0700.
    othrys.internal.persist."apps.obs" = {
      user.directories = [
        {
          directory = ".config/obs-studio";
          mode = "0700";
        }
      ];
    };

    security.polkit.enable = true;

    # The "Start Virtual Camera" button needs a v4l2loopback device to write
    # to. mkDefault lets a host that wants OBS without the kernel module turn
    # it back off.
    othrys.services.virtualcamera.enable = lib.mkDefault true;

    # User-level OBS with plugins
    othrys.internal.homeConfig."apps.obs" = {
      programs.obs-studio = {
        enable = true;
        # CUDA is only of use with the NVIDIA driver, and the override builds
        # OBS from source against the unfree CUDA toolkit, so every other host
        # takes the cached package.
        package =
          if nvidiaEnabled
          then pkgs.obs-studio.override {cudaSupport = true;}
          else pkgs.obs-studio;
        plugins = with pkgs.obs-studio-plugins; [
          wlrobs
          obs-backgroundremoval
          obs-pipewire-audio-capture
          obs-gstreamer
          obs-vkcapture
        ];
      };
    };
  };
}
