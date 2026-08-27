# modules/apps/gui/gaming/mangohud.nix
# MangoHud, a Vulkan/OpenGL overlay for FPS, temperature and CPU/GPU usage
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.gaming.mangohud;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  inherit (config.lib.stylix) colors;
in {
  options.othrys.apps.gaming.mangohud = {
    enable = lib.mkEnableOption "MangoHud performance overlay";

    enableSessionWide = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable MangoHud for all Vulkan applications via environment variable.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
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

  # The assertion lives in its own mkIf because the body interpolates Stylix colors,
  # so it must stay unevaluated when stylix is off or the deep Stylix error
  # preempts the assertion message during assertion collection.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.othrys.system.stylix.enable;
          message = "othrys.apps.gaming.mangohud requires othrys.system.stylix.enable = true (overlay colors read the Stylix palette).";
        }
      ];
    })
    (lib.mkIf (cfg.enable && config.othrys.system.stylix.enable) {
      # Persistence for MangoHud configuration
      environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
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
      home-manager.users.${username} = {
        programs.mangohud = {
          enable = true;

          # othrys defaults yield (mkDefault) to Stylix's mangohud theming
          # (colors + opacity) when Stylix is enabled, and cfg.settings still wins.
          settings =
            (lib.mapAttrs (_: lib.mkDefault) {
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

              # Colors (from Stylix theme or oxocarbon fallback)
              text_color = colors.base05;
              gpu_color = colors.base0D; # Blue
              cpu_color = colors.base08; # Cyan/Red
              vram_color = colors.base0C; # Magenta/Cyan
              ram_color = colors.base0B; # Green
              engine_color = colors.base0E; # Purple
              frametime_color = colors.base09; # Blue/Orange
              background_color = colors.base00;

              # Font
              font_size = 20;
              font_scale = 1.0;
              no_small_font = false;

              # compact_mode = true;
              # horizontal = true;
            })
            // cfg.settings;
        };
      };
    })
  ];
}
