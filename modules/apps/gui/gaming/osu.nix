# modules/apps/gui/gaming/osu.nix
# osu!lazer wrapped for low-latency audio, with a pen tablet on by default
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.othrys.apps.gaming.osu;

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
  imports = [
    (lib.mkRenamedOptionModule ["othrys" "apps" "gaming" "osu" "enableTabletDriver"] ["othrys" "hardware" "tablet" "enable"])
  ];

  options.othrys.apps.gaming.osu = {
    enable = lib.mkEnableOption "osu!lazer with low-latency optimizations";

    package = lib.mkOption {
      type = lib.types.package;
      default = osuWrapped;
      defaultText = lib.literalMD "`pkgs.osu-lazer` behind a wrapper that sets the PipeWire latency and starts it through `gamemoderun`";
      description = "osu!lazer package to use (wrapped with latency optimizations).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for osu! songs, skins, replays and scores
    othrys.internal.persist."apps.gaming.osu" = {
      user.directories = [
        ".local/share/osu"
      ];
    };

    # Most osu! players use a tablet, so the driver comes with the game unless
    # the host turns it off.
    othrys.hardware.tablet.enable = lib.mkDefault true;

    othrys.internal.homeConfig."apps.gaming.osu" = {
      home.packages = [
        cfg.package # Low-latency wrapper that calls pkgs.osu-lazer
      ];
    };
  };
}
