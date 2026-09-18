# modules/system/hardening.nix
# Opt-in kernel and sysctl hardening profile
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.system.hardening;

  # mkOverride 900 rather than mkDefault, matching ntfy.nix and docker.nix.
  # boot.kernel.sysctl refuses two definitions at one priority even when the
  # values agree, and NixOS already writes kernel.kptr_restrict at mkDefault
  # while security.protectKernelImage writes kernel.kexec_load_disabled at
  # mkDefault. 900 beats both and still loses to a plain host assignment at
  # 100, which is also how othrys.services.router keeps its strict rp_filter.
  mkProfile = lib.mkOverride 900;

  # A host that names a resume device, or passes resume= to the kernel, is
  # configured to hibernate. No othrys module models hibernation, so the
  # upstream options are the signal.
  hibernates =
    config.boot.resumeDevice
    != ""
    || lib.any (lib.hasPrefix "resume=") config.boot.kernelParams;
in {
  # ANCHOR: hardening-options
  options.othrys.system.hardening = {
    enable =
      lib.mkEnableOption "the kernel and sysctl hardening profile"
      // {
        description = ''
          Apply the low-cost kernel and network sysctl hardening profile. The
          profile is opt-in, and nothing is set while this is off.

          Every sysctl is written below the priority of a plain assignment, so a
          host overrides any single value by setting the same key under
          `boot.kernel.sysctl`. The values restrict kernel pointer and dmesg
          exposure, unprivileged BPF, ptrace and kexec, and turn off ICMP
          redirects and source routing.

          `rp_filter` is set to loose mode (2) rather than strict (1). Strict
          mode drops replies that arrive on a different interface from the
          route back to the sender, which breaks Tailscale exit nodes and
          multi-homed routers. It also overrides the loose
          `networking.firewall.checkReversePath` that the Tailscale module
          selects, since the kernel check runs regardless of the firewall.
          `othrys.services.router` assigns strict mode itself and that
          assignment wins over the profile.

          `lockKernelModules` and `protectKernelImage` are separate options
          because each one breaks something, and neither is implied by
          `enable`.
        '';
      };

    lockKernelModules = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Set `security.lockKernelModules`, which disables kernel module loading
        once the system has booted.

        No module can load after boot. Hardware plugged in later, and VPN or
        filesystem modules that were not loaded at boot, stop working until
        the next reboot. List every module the host needs later in
        `boot.kernelModules` so it is loaded before the lock.
      '';
    };

    protectKernelImage = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Set `security.protectKernelImage`, which prevents the running kernel
        image from being replaced.

        Hibernation and kexec are disabled. Evaluation fails on a host that
        sets `boot.resumeDevice` or passes `resume=` in `boot.kernelParams`,
        since such a host would lose the ability to resume.
      '';
    };
  };
  # ANCHOR_END: hardening-options

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.protectKernelImage -> !hibernates;
        message = "othrys.system.hardening.protectKernelImage disables hibernation, but this host sets boot.resumeDevice or a resume= kernel parameter. Drop one of the two.";
      }
    ];

    boot.kernel.sysctl = lib.mapAttrs (_: mkProfile) {
      "kernel.kptr_restrict" = 2;
      "kernel.dmesg_restrict" = 1;
      "kernel.unprivileged_bpf_disabled" = 1;
      "net.core.bpf_jit_harden" = 2;
      "kernel.yama.ptrace_scope" = 1;
      "kernel.kexec_load_disabled" = 1;

      "net.ipv4.conf.all.rp_filter" = 2;
      "net.ipv4.conf.default.rp_filter" = 2;

      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.ipv4.conf.all.secure_redirects" = 0;
      "net.ipv4.conf.default.secure_redirects" = 0;
      "net.ipv4.conf.all.send_redirects" = 0;
      "net.ipv4.conf.default.send_redirects" = 0;
      "net.ipv6.conf.all.accept_redirects" = 0;
      "net.ipv6.conf.default.accept_redirects" = 0;

      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;
      "net.ipv6.conf.default.accept_source_route" = 0;

      "net.ipv4.tcp_syncookies" = 1;
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      "net.ipv4.tcp_rfc1337" = 1;
    };

    security.lockKernelModules = lib.mkIf cfg.lockKernelModules true;
    security.protectKernelImage = lib.mkIf cfg.protectKernelImage true;
  };
}
