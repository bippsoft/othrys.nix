# modules/services/containerization/podman.nix
# Podman container runtime with optional Docker compatibility
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.services.containerization.podman;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  # ANCHOR: podman-options
  options.othrys.services.containerization.podman = {
    enable = lib.mkEnableOption "Podman container runtime";

    dockerCompat = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create docker alias pointing to podman for drop-in replacement.";
    };

    enableDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable DNS for default network (required for podman-compose).";
    };

    distrobox = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Distrobox for running containers as if they were native apps.";
      };
    };

    compose = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install podman-compose for docker-compose compatibility.";
      };
    };

    autoPrune = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Periodically prune unused Podman resources.";
      };

      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "systemd calendar expression for the prune timer.";
      };

      flags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["--all"];
        description = "Flags passed to `podman system prune`. `--all` removes every image without a running container; hosts that pre-pull pinned images should override this.";
      };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional packages to install alongside Podman.";
      example = lib.literalExpression "with pkgs; [ skopeo buildah ]";
    };
  };
  # ANCHOR_END: podman-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.dockerCompat -> !config.virtualisation.docker.enable;
        message = "Podman dockerCompat conflicts with virtualisation.docker.enable. Disable one of them.";
      }
    ];

    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        ".local/share/containers"
        ".config/containers"
      ];
    };

    virtualisation.containers.enable = true;

    virtualisation.podman = {
      enable = true;
      inherit (cfg) dockerCompat;

      # DNS required for containers to communicate (especially with podman-compose)
      defaultNetwork.settings.dns_enabled = cfg.enableDns;

      # Auto-prune unused images (retention policy is the consumer's call)
      autoPrune = {
        inherit (cfg.autoPrune) enable dates flags;
      };
    };

    # Guarded at the attrset level, since writing users.users.<name> for an account
    # othrys doesn't manage would materialize a phantom user on headless hosts.
    users.users = lib.mkIf usersEnabled {
      ${username}.extraGroups = ["podman"];
    };

    environment.systemPackages = with pkgs;
      [
        podman-tui # TUI for managing containers
      ]
      ++ lib.optionals cfg.compose.enable [podman-compose]
      ++ lib.optionals cfg.distrobox.enable [distrobox]
      ++ cfg.extraPackages;

    # home.shellAliases propagates to every home-manager-enabled shell
    # (bash/zsh/fish), so never write per-shell alias sets from other modules.
    othrys.internal.homeConfig."services.containerization.podman".home.shellAliases = lib.mkIf cfg.dockerCompat {
      docker-compose = "podman-compose";
    };
  };
}
