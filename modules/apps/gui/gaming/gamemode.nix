# modules/apps/gui/gaming/gamemode.nix
# GameMode configuration for gaming performance optimization (NVIDIA-friendly)
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.othrys.apps.gaming.gamemode;
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
in {
  options.othrys.apps.gaming.gamemode = {
    enable = lib.mkEnableOption "gamemode configuration for gaming optimization";

    settings = lib.mkOption {
      # The type of programs.gamemode.settings upstream, the INI format with
      # a list written as repeated keys. gamemode.ini is sections of scalar
      # keys, so anything deeper than section and key is refused here.
      inherit (pkgs.formats.ini {listsAsDuplicateKeys = true;}) type;
      default = {};
      description = ''
        Extra programs.gamemode.settings, merged over the curated defaults.
        Those are written at mkDefault, so overriding one leaf leaves its
        siblings in place and lib.mkForce replaces a leaf outright.

        The shape is that of gamemode.ini, a section name over keys whose
        values are a string, a number, a boolean or a list of those.

        One default deserves a decision.
        `gpu.apply_gpu_optimisations = "accept-responsibility"` lets gamemode
        change GPU power settings as root at every game start, for members of
        the `gamemode` group, which this module adds the primary user to. It
        then sets the AMD `power_dpm_force_performance_level` to `high`, and
        on an X11 session the NVIDIA PowerMizer mode to maximum performance.
        The NVIDIA step goes through nvidia-settings, which needs an X display
        and Coolbits, so it does nothing under a Wayland compositor. The value is spelled
        that way upstream because gamemode documents these GPU settings as
        able to damage hardware, and writing it accepts that. A host that
        does not want it sets `gpu.apply_gpu_optimisations = 0`, which leaves
        the GPU alone and keeps the CPU and scheduling changes.
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
            inhibit_screensaver = lib.mkDefault 1;
            renice = lib.mkDefault 15;
          };
          gpu = {
            # Upstream's literal for "change GPU power settings as root". The
            # option description says what the value accepts.
            apply_gpu_optimisations = lib.mkDefault "accept-responsibility";
            gpu_device = lib.mkDefault 0;
            # NVIDIA performance mode. Applied through nvidia-settings, so only
            # on an X11 session.
            nv_powermizer_mode = lib.mkDefault 1;
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

    # GameMode's polkit rule runs its root helpers, which set the CPU
    # governor, the split-lock mitigation and the GPU settings, only for
    # members of this group. Without it every helper is refused and the
    # governor stays where it was. Only when othrys manages the account, since
    # writing users.users.<name> otherwise materializes a phantom user.
    users.users = lib.mkIf usersEnabled {
      ${username}.extraGroups = ["gamemode"];
    };

    # Ensure libnotify is available for notifications
    environment.systemPackages = with pkgs; [
      libnotify
    ];
  };
}
