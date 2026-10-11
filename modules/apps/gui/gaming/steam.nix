# modules/apps/gui/gaming/steam.nix
# Steam with gaming optimizations (Proton-GE, essential runtime libraries)
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.othrys.apps.gaming.steam;

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
      default = false;
      description = ''
        Open the firewall for Steam Remote Play, which streams a game from
        this host to another device. It opens TCP 27036 and 27037 and UDP
        10400, 10401 and 27031 to 27036 on every interface. Off by default,
        so a host that streams turns it on.
      '';
    };

    dedicatedServer.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open firewall ports for Source Dedicated Server, TCP and UDP 27015.
        Off by default, as the other two firewall options are.
      '';
    };

    localNetworkGameTransfers.openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the firewall for Steam Local Network Game Transfers, which
        copies an installed game from another Steam client on the network
        instead of downloading it. It opens TCP 27040 for the transfer and
        UDP 27036 for peer discovery on every interface. Off by default, so
        a host that shares its library turns it on.
      '';
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
    othrys.internal.persist."apps.gaming.steam" = {
      user.directories = [
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

      # The session also turns on programs.gamescope, which is how gamescope
      # reaches the system path. programs.gamescope.capSysNice stays off on
      # purpose. The setcap wrapper it installs cannot run inside Steam's
      # bubblewrap sandbox, where gamescope in a game's launch options then
      # dies with "failed to inherit capabilities". NixOS/nixpkgs#351516
      # tracks it.
      gamescopeSession.enable = cfg.gamescopeSession.enable;
    };

    # The file sits inside the Steam tree persisted above, so the home-manager
    # symlink survives a reboot on impermanence hosts. Steam only reads the
    # file, which makes a store symlink safe there. The condition wraps the
    # value of this module's key, so an empty devConfig drops the key and the
    # rest of the registry is defined unconditionally.
    othrys.internal.homeConfig."apps.gaming.steam" = lib.mkIf (devConfig != {}) {
      home.file.".local/share/Steam/steam_dev.cfg".text = devConfigText;
    };
  };
}
