# flake/modules.nix
# Exports nixosModules for use by other flakes.
#
# `default` aggregates the entire module tree (system, desktop, hardware,
# services, apps). Every reusable *infrastructure* module (system, desktop,
# hardware, services) is ALSO exported individually below so a consumer can
# import just one without the whole tree. App modules (modules/apps/**) are
# personal-workflow-shaped and reachable only via `default`.
#
# Rule of thumb when adding a module. If it lives outside modules/apps/, add an
# individual export here. The `eval-default` check (flake/checks/) fails if
# the aggregate stops evaluating, but it does NOT verify this list is complete,
# keep it in sync by following the rule above.
#
# Several modules write into option namespaces
# owned by upstream flakes (disko, home-manager, stylix, sops-nix,
# impermanence). A consumer of `default` must also import those flakes'
# nixosModules, see docs/src/architecture/host-configuration.md. This holds
# even when the corresponding othrys feature is disabled.
#
# Usage from another flake:
#   inputs.othrys.nixosModules.default
#   inputs.othrys.nixosModules.impermanence
{inputs, ...}: {
  flake.nixosModules = {
    # Aggregate of the full module tree. Injects this flake's own source as the
    # `othrysSelf` module arg for modules that build from it (services/docs.nix),
    # so consumers don't need to thread it through specialArgs.
    default = {
      imports = [../modules];
      _module.args.othrysSelf = inputs.self;
    };

    # System fundamentals
    disko = ../modules/system/disko.nix;
    locale = ../modules/system/locale.nix;
    user = ../modules/system/user.nix;
    users = ../modules/system/users.nix;
    nix = ../modules/system/nix.nix;
    kernel = ../modules/system/kernel.nix;
    networking = ../modules/system/networking.nix;
    secrets = ../modules/system/secrets.nix;
    impermanence = ../modules/system/impermanence.nix;
    persistence = ../modules/system/persistence.nix;
    bootloader = ../modules/system/bootloader.nix;
    git = ../modules/system/git.nix;

    # Desktop environment and compositors
    hyprland = ../modules/desktop/compositors/hyprland.nix;
    stylix = ../modules/system/stylix.nix;
    uwsm = ../modules/desktop/uwsm.nix;

    # Hardware-specific
    audio = ../modules/hardware/audio.nix;
    bluetooth = ../modules/hardware/wireless/bluetooth.nix;
    wifi = ../modules/hardware/wireless/wifi.nix;
    nvidia = ../modules/hardware/graphics/nvidia.nix;
    nvidia-prime = ../modules/hardware/graphics/prime.nix;
    laptop = ../modules/hardware/laptop/default.nix;

    # Background services
    printing = ../modules/services/printing.nix;
    ssh = ../modules/services/ssh.nix;
    tailscale = ../modules/services/tailscale.nix;
    headscale = ../modules/services/headscale.nix;
    monitoring = ../modules/services/monitoring.nix;
    firewall = ../modules/services/firewall.nix;
    router = ../modules/services/router.nix;
    suricata = ../modules/services/suricata.nix;
    kea = ../modules/services/kea.nix;
    unbound = ../modules/services/unbound.nix;
    restic = ../modules/services/restic.nix;
    traefik = ../modules/services/traefik.nix;
    docs = ../modules/services/docs.nix;
    virtualcamera = ../modules/services/virtualcamera.nix;
    automount = ../modules/services/automount.nix;
    mounts-disks = ../modules/services/mounts/disks.nix;
    mounts-cifs = ../modules/services/mounts/cifs.nix;

    # Containerization
    docker = ../modules/services/containerization/docker.nix;
    podman = ../modules/services/containerization/podman.nix;
    k3s = ../modules/services/containerization/k3s.nix;

    # Security features
    sudo = ../modules/services/security/sudo.nix;
    polkit = ../modules/services/security/polkit.nix;
    yubikey = ../modules/services/security/yubikey.nix;
    fail2ban = ../modules/services/security/fail2ban.nix;
    crowdsec = ../modules/services/security/crowdsec.nix;

    # Shell environment
    zsh = ../modules/system/shell/zsh.nix;
    starship = ../modules/system/shell/starship.nix;
  };
}
