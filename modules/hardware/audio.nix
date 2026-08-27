# modules/hardware/audio.nix
# PipeWire audio stack
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.hardware.audio;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.hardware.audio = {
    enable = lib.mkEnableOption "PipeWire audio stack";

    lowLatency = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable low-latency audio configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for audio configuration and state
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories = [
        ".config/pulse"
        ".local/state/wireplumber"
      ];
    };

    # GUI mixer only on desktop hosts. Headless audio boxes (media servers,
    # BT sinks) use wpctl/pactl and skip the GTK closure.
    environment.systemPackages = lib.optionals config.othrys.desktop.graphical [
      pkgs.pavucontrol
    ];

    # Disable PulseAudio
    services.pulseaudio.enable = false;

    # Enable PipeWire
    services.pipewire = {
      enable = true;
      audio.enable = true;

      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;

      # Low-latency configuration
      extraConfig.pipewire = lib.mkIf cfg.lowLatency {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 512;
          "default.clock.min-quantum" = 256;
          "default.clock.max-quantum" = 2048;
        };
      };

      # Prefer duplex (output+input) profiles for USB audio devices
      wireplumber.extraConfig."99-usb-audio-duplex" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {"device.bus" = "usb";}
            ];
            actions = {
              update-props = {
                "device.profile" = "output:analog-stereo+input:mono-fallback";
              };
            };
          }
        ];
      };
    };

    # Real-time scheduling for audio
    security.rtkit.enable = true;
  };
}
