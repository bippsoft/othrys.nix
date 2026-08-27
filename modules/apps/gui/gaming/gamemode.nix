# modules/apps/gui/gaming/gamemode.nix
# GameMode configuration for gaming performance optimization (NVIDIA-friendly)
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.othrys.apps.gaming.gamemode;
in {
  options.othrys.apps.gaming.gamemode = {
    enable = lib.mkEnableOption "gamemode configuration for gaming optimization";

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        general = {
          softrealtime = "auto";
          inhibit_screensaver = 1;
          renice = 15;
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
          # NVIDIA performance settings
          nv_powermizer_mode = 1; # Performance mode
          # AMD settings kept for compatibility but won't be used
          amd_performance_level = "high";
        };
        custom = {
          start = "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Performance optimizations active' --icon=applications-games";
          end = "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Performance optimizations inactive' --icon=applications-games";
        };
      };
      description = "Gamemode configuration settings.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.gamemode = {
      enable = true;
      enableRenice = true;
      settings = lib.mkDefault cfg.settings;
    };

    # Ensure libnotify is available for notifications
    environment.systemPackages = with pkgs; [
      libnotify
    ];
  };
}
