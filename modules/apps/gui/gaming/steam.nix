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

  # The client reads steam_dev.cfg at start, one console variable per line.
  # The typed shaderPrecache options are merged over the raw devConfig set, so
  # a typed key wins a duplicate.
  devConfig =
    cfg.devConfig
    // lib.filterAttrs (_: v: v != null) {
      unShaderBackgroundProcessingThreads = cfg.shaderPrecache.backgroundThreads;
      unShaderHighPriorityProcessingThreads = cfg.shaderPrecache.highPriorityThreads;
    };

  renderDevValue = v:
    if lib.isBool v
    then
      (
        if v
        then "1"
        else "0"
      )
    else toString v;

  devConfigText =
    lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} ${renderDevValue v}") devConfig)
    + "\n";
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
      default = config.programs.steam.package;
      defaultText = lib.literalExpression "config.programs.steam.package";
      description = ''
        The Steam package as installed, after nixpkgs adds the graphics
        drivers, fonts, and compatibility tool paths to the FHS environment.
        Read this when wrapping Steam, since a package taken before that step
        starts without a working GPU driver.
      '';
    };

    remotePlay.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open firewall ports for Steam Remote Play.";
    };

    dedicatedServer.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open firewall ports for Source Dedicated Server, TCP and UDP 27015.
        Off by default, since a host that plays games does not also serve
        them, while Remote Play and LAN transfers are client features and
        stay open.
      '';
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

    shaderPrecache = {
      backgroundThreads = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 12;
        description = ''
          CPU threads given to Steam's fossilize shader pre-caching while it
          runs in the background, written as
          `unShaderBackgroundProcessingThreads` in `steam_dev.cfg`. The pass
          only runs while "Allow background processing of Vulkan shaders" is
          enabled in Steam under Settings, Downloads. That toggle is off by
          default and lives in Steam's own registry, which this module cannot
          declare. Null leaves Steam's heuristic in place. The value is a host
          sizing decision, since a desktop can spare most of `nproc` while a
          laptop wants a fraction of it.
        '';
      };

      highPriorityThreads = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 24;
        description = ''
          CPU threads for the "Processing Vulkan shaders" pass that blocks a
          game launch, written as `unShaderHighPriorityProcessingThreads` in
          `steam_dev.cfg`. Steam deletes every compiled cache when the GPU
          driver version changes, so each game pays this pass once after a
          driver update. With the variable unset the pass was measured at
          about 16 pipelines per second on a 32-thread desktop, where the same
          replay reaches 223 per second at 28 threads. Valve documents neither
          variable. The background one is confirmed by wide use, while this
          one is known only from the client binary, where its name places it
          on the pre-launch pass. Null leaves Steam's default.
        '';
      };
    };

    devConfig = lib.mkOption {
      type = lib.types.attrsOf (lib.types.oneOf [lib.types.int lib.types.str lib.types.bool]);
      default = {};
      example = lib.literalExpression ''
        {
          "@nClientDownloadEnableHTTP2PlatformLinux" = 0;
          "@fDownloadRateImprovementToAddAnotherConnection" = "1.0";
        }
      '';
      description = ''
        Additional Steam console variables written to
        `~/.local/share/Steam/steam_dev.cfg`, one `name value` per line.
        These are the variables accepted by the Steam console at
        `steam://open/console`, applied at every client start. The
        `shaderPrecache` options render into the same file and take
        precedence over a duplicate key here.
      '';
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

      package = configuredSteam;

      # Use combined list of default + user extras
      extraCompatPackages = finalCompatPackages;

      gamescopeSession.enable = cfg.gamescopeSession.enable;
    };

    # The file sits inside the Steam tree persisted above, so the home-manager
    # symlink survives a reboot on impermanence hosts. Steam only reads the
    # file, which makes a store symlink safe there.
    othrys.internal.homeConfig = lib.mkIf (devConfig != {}) {
      "apps.gaming.steam" = {
        home.file.".local/share/Steam/steam_dev.cfg".text = devConfigText;
      };
    };
  };
}
