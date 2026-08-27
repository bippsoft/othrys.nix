# modules/apps/gui/gaming/steam.nix
# Steam with gaming optimizations (Proton-GE, essential runtime libraries)
{
  pkgs,
  lib,
  config,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.gaming.steam;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # Default Proton compatibility packages
  defaultCompatPackages = with pkgs; [
    proton-ge-bin
  ];

  finalCompatPackages = defaultCompatPackages ++ cfg.extraCompatPackages;

  # Configure Steam with extra packages in FHS environment
  configuredSteam = pkgs.steam.override {
    inherit (cfg) extraPkgs;
  };
in {
  options.othrys.apps.gaming.steam = {
    enable = lib.mkEnableOption "Steam with gaming optimizations";

    extraCompatPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "with pkgs; [ ]";
      description = "Additional Proton compatibility packages to add to the defaults (proton-ge-bin).";
    };

    extraPkgs = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = pkgs:
        with pkgs;
          [
            # X11 libraries (required for many games)
            libxcursor
            libxi
            libxinerama
            libxscrnsaver

            # System libraries
            stdenv.cc.cc.lib
            keyutils
            libkrb5
            libpng
            libpulseaudio
            libvorbis
          ]
          ++ lib.optionals config.othrys.apps.gaming.gamemode.enable [gamemode];
      description = "Extra packages to include in Steam's FHS runtime environment.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = configuredSteam;
      description = "The configured Steam package with extra packages.";
    };

    remotePlay.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for Steam Remote Play.";
    };

    dedicatedServer.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for Source Dedicated Server.";
    };

    localNetworkGameTransfers.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for Steam Local Network Game Transfers.";
    };

    gamescopeSession.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GameScope session for Steam Deck-like experience.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for Steam library and game saves
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".local/share/Steam"
        ".steam"
        ".local/share/vulkan"
      ];
    };

    programs.steam = {
      enable = true;

      remotePlay.openFirewall = cfg.remotePlay.openFirewall;
      dedicatedServer.openFirewall = cfg.dedicatedServer.openFirewall;
      localNetworkGameTransfers.openFirewall = cfg.localNetworkGameTransfers.openFirewall;

      protontricks = {
        enable = lib.mkDefault true;
        package = lib.mkDefault pkgs.protontricks;
      };

      inherit (cfg) package;

      # Use combined list of default + user extras
      extraCompatPackages = finalCompatPackages;

      gamescopeSession.enable = cfg.gamescopeSession.enable;
    };

    # Environment variables for Steam
    environment.sessionVariables = {
      STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
    };
  };
}
