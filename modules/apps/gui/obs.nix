# modules/apps/gui/obs.nix
# OBS Studio with its Wayland, PipeWire and Vulkan capture plugins
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.obs;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.obs = {
    enable = lib.mkEnableOption "OBS Studio with virtual camera";
  };

  config = lib.mkIf cfg.enable {
    # Scenes, profiles and the stream service settings, which carry the stream
    # key in plaintext, so the directory is 0700.
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        {
          directory = ".config/obs-studio";
          mode = "0700";
        }
      ];
    };

    security.polkit.enable = true;

    # User-level OBS with plugins
    othrys.internal.homeConfig."apps.obs" = {
      programs.obs-studio = {
        enable = true;
        package = pkgs.obs-studio.override {cudaSupport = true;};
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
