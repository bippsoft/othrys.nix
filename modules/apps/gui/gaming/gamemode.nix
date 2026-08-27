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
      default = {};
      description = ''
        Extra programs.gamemode.settings, merged over the curated defaults.
        Those are written at mkDefault, so overriding one leaf leaves its
        siblings in place and lib.mkForce replaces a leaf outright.
      '';
      example = lib.literalExpression ''
        {
          general.renice = 10;
          gpu.amd_performance_level = "high";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.gamemode = {
      enable = true;
      enableRenice = true;

      # Curated defaults are written here rather than as the option's default,
      # since an option default is discarded wholesale by any definition and a
      # consumer setting one nested key would silently lose the rest. Per-leaf
      # mkDefault hands the layering to the module system.
      settings = lib.mkMerge [
        {
          general = {
            softrealtime = lib.mkDefault "auto";
            inhibit_screensaver = lib.mkDefault 1;
            renice = lib.mkDefault 15;
          };
          gpu = {
            apply_gpu_optimisations = lib.mkDefault "accept-responsibility";
            gpu_device = lib.mkDefault 0;
            nv_powermizer_mode = lib.mkDefault 1; # NVIDIA performance mode
            # Inert on NVIDIA hosts, present so an AMD host inherits a sane value.
            amd_performance_level = lib.mkDefault "high";
          };
          custom = {
            start = lib.mkDefault "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Performance optimizations active' --icon=applications-games";
            end = lib.mkDefault "${pkgs.libnotify}/bin/notify-send 'GameMode' 'Performance optimizations inactive' --icon=applications-games";
          };
        }
        cfg.settings
      ];
    };

    # Ensure libnotify is available for notifications
    environment.systemPackages = with pkgs; [
      libnotify
    ];
  };
}
