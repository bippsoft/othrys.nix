# modules/services/containerization/docker.nix
# Docker container runtime with rootless mode and NVIDIA support
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.services.containerization.docker;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  nvidiaEnabled = config.othrys.hardware.nvidia.enable;

  # Daemon defaults, merged into both the rootful and rootless settings.
  #
  # mkDefault sits on each leaf rather than on the attrset, so a consumer
  # setting daemon.settings.log-driver overrides that one key and still gets the
  # generated storage-driver. A priority applies to a whole definition, so one
  # mkDefault covering both would be discarded entirely the moment either key is
  # named. Without the defaults at all, the two definitions collide and the
  # override the description promises is an evaluation error instead.
  daemonSettings = lib.mkMerge [
    {
      log-driver = lib.mkDefault "journald";
      storage-driver = lib.mkDefault "overlay2";
    }
    cfg.daemon.settings
  ];
in {
  options.othrys.services.containerization.docker = {
    enable = lib.mkEnableOption "Docker container runtime";

    rootless = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run Docker in rootless mode for improved security.";
      };

      setSocketVariable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set DOCKER_HOST environment variable for rootless mode.";
      };
    };

    nvidia = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable NVIDIA container runtime for GPU workloads.
          This sets hardware.nvidia-container-toolkit.enable = true.
        '';
      };
    };

    compose = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install docker-compose.";
      };
    };

    autoPrune = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Periodically prune unused Docker resources.";
      };

      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "systemd calendar expression for the prune timer.";
      };

      flags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["--all"];
        example = ["--all" "--volumes"];
        description = ''
          Flags passed to `docker system prune`. The default deliberately
          omits `--volumes`: it deletes anonymous volumes of every container
          not currently running, which silently destroys data belonging to
          stopped or on-demand containers. Opt in explicitly if you want it.
        '';
      };
    };

    daemon = {
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        description = "Additional Docker daemon settings (merged with defaults).";
        example = lib.literalExpression ''
          {
            dns = [ "1.1.1.1" "8.8.8.8" ];
            registry-mirrors = [ "https://mirror.gcr.io" ];
          }
        '';
      };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install alongside Docker.";
      example = lib.literalExpression "with pkgs; [ dive ]";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.nvidia.enable -> nvidiaEnabled;
        message = "Docker NVIDIA support requires othrys.hardware.nvidia.enable = true";
      }
      {
        assertion = !(cfg.rootless.enable && cfg.nvidia.enable);
        message = "Docker rootless mode is incompatible with NVIDIA container runtime. Disable rootless or nvidia.enable.";
      }
    ];

    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      # System-level Docker data (when not rootless)
      directories = lib.mkIf (!cfg.rootless.enable) [
        {
          directory = "/var/lib/docker";
          user = "root";
          group = "root";
          mode = "0710";
        }
      ];

      # User-level Docker data (for rootless mode), only when othrys manages
      # the user account.
      users = lib.mkIf (usersEnabled && cfg.rootless.enable) {
        ${username}.directories = [
          ".local/share/docker"
          ".docker"
        ];
      };
    };

    hardware.nvidia-container-toolkit.enable = cfg.nvidia.enable;

    virtualisation.docker = {
      enable = true;

      # Daemon settings
      daemon.settings = daemonSettings;

      # Rootless mode configuration
      rootless = lib.mkIf cfg.rootless.enable {
        enable = true;
        inherit (cfg.rootless) setSocketVariable;
        daemon.settings = daemonSettings;
      };

      # Auto-prune unused resources (retention policy is the consumer's call)
      autoPrune = {
        inherit (cfg.autoPrune) enable dates flags;
      };
    };

    # Guarded at the attrset level, since writing users.users.<name> for an account
    # othrys doesn't manage would materialize a phantom user on headless hosts.
    users.users = lib.mkIf (usersEnabled && !cfg.rootless.enable) {
      ${username}.extraGroups = ["docker"];
    };

    environment.systemPackages = with pkgs;
      [
        lazydocker # TUI for Docker management
      ]
      ++ lib.optionals cfg.compose.enable [docker-compose]
      ++ cfg.extraPackages;

    # home.shellAliases propagates to every home-manager-enabled shell
    # (bash/zsh/fish), so never write per-shell alias sets from other modules.
    othrys.internal.homeConfig."services.containerization.docker".home.shellAliases = {
      lzd = "lazydocker";
    };
  };
}
