# modules/apps/gui/gaming/r2modman.nix
# r2modman, the Thunderstore mod manager for Unity games
{
  pkgs,
  lib,
  config,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.apps.gaming.r2modman;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # Wrap r2modman with Wayland flags to fix blurry rendering
  # r2modman is an Electron app that needs Ozone platform for crisp Wayland rendering
  r2modmanWayland = pkgs.r2modman.overrideAttrs (oldAttrs: {
    postFixup =
      (oldAttrs.postFixup or "")
      + ''
        wrapProgram $out/bin/r2modman \
          --add-flags "--enable-features=UseOzonePlatform --ozone-platform=wayland"
      '';
  });
in {
  options.othrys.apps.gaming.r2modman = {
    enable = lib.mkEnableOption "r2modman Thunderstore mod manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = r2modmanWayland;
      description = "r2modman package to use (wrapped for Wayland by default).";
    };
  };

  config = lib.mkIf cfg.enable {
    # r2modman requires Steam to launch modded games
    assertions = [
      {
        assertion = config.othrys.apps.gaming.steam.enable;
        message = "othrys.apps.gaming.r2modman requires othrys.apps.gaming.steam.enable = true. r2modman launches games through Steam with mod profiles.";
      }
    ];

    # Profiles, settings and the downloaded mod cache. The files r2modman
    # injects into a game survive with the Steam tree, so without this the
    # manager forgets the profile that put them there.
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        ".config/r2modmanPlus-local"
      ];
    };

    othrys.internal.homeConfig."apps.gaming.r2modman" = {
      home.packages = [
        cfg.package
        pkgs.mono # Required for executing .NET/C# mods in Unity games
      ];
    };
  };
}
