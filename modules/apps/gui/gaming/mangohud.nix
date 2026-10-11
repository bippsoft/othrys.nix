# modules/apps/gui/gaming/mangohud.nix
# MangoHud, a Vulkan/OpenGL overlay for FPS, temperature and CPU/GPU usage
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.gaming.mangohud;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  inherit (config.othrys.theme) palette;
in {
  options.othrys.apps.gaming.mangohud = {
    enable = lib.mkEnableOption "MangoHud performance overlay";

    enableSessionWide = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable MangoHud for all Vulkan applications via environment variable.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "MangoHud settings merged over (and overriding) the curated defaults.";
      example = lib.literalExpression ''
        {
          position = "top-left";
          fps_limit = 60;
          gpu_temp = false;
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for MangoHud configuration
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        ".config/MangoHud"
        ".local/share/MangoHud"
      ];
    };

    # System-wide, since the overlay must load into the graphics stack for every
    # Vulkan/GL app, so the package is system-level while its config (below)
    # stays in home-manager. See the Package Placement section of CONTRIBUTING.md..
    environment.systemPackages = with pkgs; [
      mangohud
    ];

    # Session-wide enable via environment variable
    environment.sessionVariables = lib.mkIf cfg.enableSessionWide {
      MANGOHUD = "1";
    };

    # Home-manager configuration for MangoHud
    othrys.internal.homeConfig."apps.gaming.mangohud" = {
      programs.mangohud = {
        enable = true;

        # Every othrys value is a default, so a module that themes the
        # overlay itself takes precedence, and cfg.settings still wins.
        settings =
          (lib.mapAttrs (_: lib.mkDefault) ({
              # Display Position
              position = "top-right";
              round_corners = 8;
              background_alpha = 0.5;

              # Performance Metrics
              fps = true;
              frametime = true;
              frame_timing = true;

              # CPU Metrics
              cpu_stats = true;
              cpu_temp = true;
              cpu_power = true;
              cpu_mhz = true;

              # GPU Metrics
              gpu_stats = true;
              gpu_temp = true;
              gpu_power = true;
              gpu_core_clock = true;
              gpu_mem_clock = true;
              gpu_mem_temp = true;
              vram = true;
              gpu_fan = true;

              # Memory
              ram = true;

              # Additional Info
              engine_version = true;
              vulkan_driver = true;
              wine = true;
              gamemode = true;

              # FPS Limit (0 = unlimited)
              fps_limit = 0;

              # Logging (F2 to start/stop)
              toggle_logging = "F2";
              output_folder = "~/.local/share/MangoHud/logs";
              log_duration = 30;

              toggle_hud = "Shift_R";
              toggle_hud_position = "Shift_R+F1";

              # Font
              font_size = 20;
              font_scale = 1.0;
              no_small_font = false;

              # compact_mode = true;
              # horizontal = true;
            }
            # Colours from the theme palette. Without one the overlay keeps
            # MangoHud's own colours.
            // lib.optionalAttrs (palette != null) {
              text_color = palette.base05;
              gpu_color = palette.base0D; # Blue
              cpu_color = palette.base08; # Red
              vram_color = palette.base0C; # Cyan
              ram_color = palette.base0B; # Green
              engine_color = palette.base0E; # Purple
              frametime_color = palette.base09; # Orange
              background_color = palette.base00;
            }))
          // cfg.settings;
      };
    };
  };
}
