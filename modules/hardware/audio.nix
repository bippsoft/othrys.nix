# modules/hardware/audio.nix
# PipeWire audio stack
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.hardware.audio;
in {
  options.othrys.hardware.audio = {
    enable = lib.mkEnableOption "PipeWire audio stack";

    lowLatency = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Halve the PipeWire graph quantum, from the stock 1024 frames to 512.
        At 48 kHz that is 10.7 ms of buffering per cycle in place of 21.3 ms.
        A client can still ask for less, down to the PipeWire minimum.
      '';
    };

    usbDuplexProfile = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Pin every USB audio device to the
        `output:analog-stereo+input:mono-fallback` profile, which suits a
        headset that WirePlumber otherwise brings up output-only. A device
        without that profile, such as a multichannel interface, is left with
        no profile and stays silent, so this is off unless a host asks for it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Persistence for audio configuration and state
    othrys.internal.persist."hardware.audio" = {
      user.directories = [
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

      # PipeWire ships a quantum of 1024 frames, 21.3 ms at 48 kHz, which is
      # audible as lag in games and in monitoring. 512 halves it and still
      # runs without dropouts on ordinary hardware. The rate and the quantum
      # bounds stay at the PipeWire values. A raised minimum would stop a
      # client from asking for a smaller buffer, which works against the
      # setting.
      extraConfig.pipewire = lib.mkIf cfg.lowLatency {
        "context.properties"."default.clock.quantum" = 512;
      };

      wireplumber.extraConfig."99-usb-audio-duplex" = lib.mkIf cfg.usbDuplexProfile {
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
