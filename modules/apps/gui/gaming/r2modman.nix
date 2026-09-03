# modules/apps/gui/gaming/r2modman.nix
# r2modman, the Thunderstore mod manager for Unity games
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.othrys.apps.gaming.r2modman;

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

    othrys.internal.homeConfig."apps.gaming.r2modman" = {
      home.packages = [
        cfg.package
        pkgs.mono # Required for executing .NET/C# mods in Unity games
      ];
    };
  };
}
