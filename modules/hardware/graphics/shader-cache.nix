# modules/hardware/graphics/shader-cache.nix
# GPU driver shader disk caches, size-tuned and persisted. Steam's fossilize
# pre-caching and per-app cache redirects live inside the persisted Steam
# tree (see apps/gui/gaming/steam.nix), but the DRIVER caches they warm live
# in ~/.cache, which impermanence wipes every boot, and NVIDIA's cache is
# capped at 1 GiB with background eviction. Modern Vulkan titles blow past
# that cap, so the driver evicts what fossilize just compiled and every
# launch recompiles from zero (CS2 reports it as a corrupted shader cache).
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
  cfg = config.othrys.hardware.graphics.shaderCache;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  nvidiaEnabled = config.othrys.hardware.nvidia.enable;
in {
  # ANCHOR: shader-cache-options
  options.othrys.hardware.graphics.shaderCache = {
    enable = lib.mkEnableOption "persistent, size-tuned GPU shader disk caches";

    nvidiaSizeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = ''
        NVIDIA shader disk cache cap (`__GL_SHADER_DISK_CACHE_SIZE`). The
        driver default is 1 GiB, under which it evicts previously compiled
        shaders, undoing Steam's shader pre-caching and forcing per-launch
        recompiles in large Vulkan titles. Size for the shader footprint of
        the games actually played; eviction is also disabled outright via
        `__GL_SHADER_DISK_CACHE_SKIP_CLEANUP`, so a host that stops playing
        a title reclaims its space by deleting `~/.cache/nvidia`.
      '';
    };
  };
  # ANCHOR_END: shader-cache-options

  config = lib.mkIf cfg.enable {
    # Session-wide rather than per-game, since Steam redirects the cache PATH per app
    # before launch, but the driver reads the size/cleanup tuning from the
    # process environment, since launch options are too late for the background
    # cleanup thread, which runs in every GL/Vulkan process.
    environment.sessionVariables = lib.mkIf nvidiaEnabled {
      __GL_SHADER_DISK_CACHE_SIZE = toString (cfg.nvidiaSizeGiB * 1024 * 1024 * 1024);
      __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
    };

    # Driver caches for everything launched OUTSIDE Steam's per-app redirect
    # (compositor, Xwayland, gamescope, browsers, native GL apps). Mesa dirs
    # are persisted on NVIDIA hosts too, since Xwayland, an iGPU or software
    # fallback still compile through mesa there.
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      users.${username}.directories =
        [
          ".cache/mesa_shader_cache"
          ".cache/mesa_shader_cache_db"
        ]
        ++ lib.optionals nvidiaEnabled [
          ".cache/nvidia"
        ];
    };
  };
}
