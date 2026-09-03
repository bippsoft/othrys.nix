# modules/apps/gui/gaming/osu.nix
# osu!lazer wrapped for low-latency audio, with OpenTabletDriver support
{
  pkgs,
  lib,
  config,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.gaming.osu;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  osuWrapped = pkgs.symlinkJoin {
    name = "osu-lazer-wrapped";
    paths = [
      (pkgs.writeShellScriptBin "osu!" ''
        # Audio Latency Tweaks (1.3ms target at 48kHz)
        export PIPEWIRE_LATENCY="64/48000"
        export PIPEWIRE_ALSA="64/48000"

        exec ${pkgs.gamemode}/bin/gamemoderun ${pkgs.osu-lazer}/bin/osu! "$@"
      '')
    ];
    postBuild = ''
      mkdir -p $out/share/applications
      cat > $out/share/applications/osu.desktop <<EOF
      [Desktop Entry]
      Name=osu!
      Comment=Rhythm is just a click away (Low-Latency + GameMode)
      Exec=$out/bin/osu! %U
      Icon=osu
      Terminal=false
      Type=Application
      Categories=Game;
      StartupNotify=true
      StartupWMClass=osu!
      PrefersNonDefaultGPU=true
      EOF

      if [ -d "${pkgs.osu-lazer}/share/icons" ]; then
        cp -r ${pkgs.osu-lazer}/share/icons $out/share/
      fi
      if [ -d "${pkgs.osu-lazer}/share/pixmaps" ]; then
        cp -r ${pkgs.osu-lazer}/share/pixmaps $out/share/
      fi
    '';
  };
in {
  options.othrys.apps.gaming.osu = {
    enable = lib.mkEnableOption "osu!lazer with OpenTabletDriver and low-latency optimizations";

    package = lib.mkOption {
      type = lib.types.package;
      default = osuWrapped;
      description = "osu!lazer package to use (wrapped with latency optimizations).";
    };

    enableTabletDriver = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OpenTabletDriver for pen tablet support.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for osu! songs, skins, replays, scores and tablet settings
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".local/share/osu"
        ".config/OpenTabletDriver"
      ];
    };

    hardware.opentabletdriver = lib.mkIf cfg.enableTabletDriver {
      enable = true;
      daemon.enable = true;
    };

    othrys.internal.homeConfig."apps.gaming.osu" = {
      home.packages = [
        cfg.package # Low-latency wrapper that calls pkgs.osu-lazer
        pkgs.opentabletdriver # GUI for tablet configuration
      ];
    };
  };
}
