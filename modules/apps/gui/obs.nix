# modules/apps/gui/obs.nix
# OBS Studio - Integration Pattern (system + user config)
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.obs;
in {
  options.othrys.apps.obs = {
    enable = lib.mkEnableOption "OBS Studio with virtual camera";
  };

  config = lib.mkIf cfg.enable {
    security.polkit.enable = true;

    # User-level OBS with plugins
    home-manager.users.${username} = {
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
