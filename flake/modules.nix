# flake/modules.nix
# Exports nixosModules for use by other flakes.
#
# `default` aggregates the entire module tree (system, theme, desktop,
# hardware, services, apps). Every reusable infrastructure module (system,
# theme, desktop, hardware, services) is also exported individually below so a
# consumer can import just one without the whole tree. App modules
# (modules/apps/**) are personal-workflow-shaped and reachable only via
# `default`.
#
# `stylix` is the one export `default` leaves out. It is the adapter between
# othrys.theme and Stylix, and a host imports it together with the Stylix
# module or imports neither.
#
# Rule when adding a module. If it lives outside modules/apps/, add an
# individual export here. The `eval-exports` check (flake/checks/) lists the
# tree and fails when a module file is missing from this list or an export
# points at a file that no longer exists.
#
# An individual export is one file, and most of them read options declared
# in other files. The primary user and the home-manager registry come from
# system/user.nix and system/users.nix, the persist root from
# system/impermanence.nix, the default editor from system/shell, the
# graphical signal from desktop/default.nix and the notification hook from
# services/notify.nix. The palette and fonts come from theme/default.nix.
# Import `system` beside any individual export, `theme` beside one that draws
# colour, and `desktop` beside a desktop or hardware one, or use `default`.
#
# Several modules write into option namespaces owned by upstream flakes
# (disko, home-manager, sops-nix, impermanence). A consumer of `default` must
# also import those flakes' nixosModules, see
# docs/src/architecture/host-configuration.md. This holds even when the
# corresponding othrys feature is disabled.
#
# Usage from another flake:
#   inputs.othrys.nixosModules.default
#   inputs.othrys.nixosModules.system
#   inputs.othrys.nixosModules.impermanence
{inputs, ...}: {
  flake.nixosModules = {
    # Aggregate of the full module tree. Injects this flake's own source as the
    # `othrysSelf` module arg for modules that build from it (services/docs.nix),
    # so consumers don't need to thread it through specialArgs.
    #
    # niri-flake's module is imported here and not inside the tree. An import
    # is evaluated on every host, and a module can only reach `inputs` through
    # the consumer's specialArgs, so importing it from modules/ made every
    # consumer declare a niri input whether or not they used niri. Here it
    # comes from this flake's own lock.
    default = {
      imports = [
        ../modules
        inputs.niri.nixosModules.niri
      ];
      _module.args.othrysSelf = inputs.self;
    };

    # The option-declaring groups, imported beside an individual export.
    system = ../modules/system;
    theme = ../modules/theme;
    desktop = ../modules/desktop;

    # The Stylix adapter, which `default` does not import. A host that wants
    # Stylix imports this and the Stylix module together.
    stylix = ../modules/theme/stylix.nix;

    # System fundamentals
    disko = ../modules/system/disko.nix;
    locale = ../modules/system/locale.nix;
    user = ../modules/system/user.nix;
    users = ../modules/system/users.nix;
    nix = ../modules/system/nix.nix;
    kernel = ../modules/system/kernel.nix;
    hardening = ../modules/system/hardening.nix;
    networking = ../modules/system/networking.nix;
    secrets = ../modules/system/secrets.nix;
    impermanence = ../modules/system/impermanence.nix;
    persistence = ../modules/system/persistence.nix;
    bootloader = ../modules/system/bootloader.nix;
    git = ../modules/system/git.nix;
    auto-upgrade = ../modules/system/auto-upgrade.nix;

    # Desktop environment and compositors
    hyprland = ../modules/desktop/compositors/hyprland.nix;
    niri = ../modules/desktop/compositors/niri.nix;
    uwsm = ../modules/desktop/uwsm.nix;
    login = ../modules/desktop/login.nix;
    idle = ../modules/desktop/idle.nix;
    night-light = ../modules/desktop/night-light.nix;
    keyring = ../modules/desktop/keyring.nix;
    ashell = ../modules/desktop/ashell;

    # Hardware-specific
    audio = ../modules/hardware/audio.nix;
    bluetooth = ../modules/hardware/wireless/bluetooth.nix;
    wifi = ../modules/hardware/wireless/wifi.nix;
    nvidia = ../modules/hardware/graphics/nvidia.nix;
    nvidia-prime = ../modules/hardware/graphics/prime.nix;
    shader-cache = ../modules/hardware/graphics/shader-cache.nix;
    laptop = ../modules/hardware/laptop/default.nix;
    powerspec-1710 = ../modules/hardware/laptop/powerspec-1710.nix;
    scanner = ../modules/hardware/scanner.nix;
    smart = ../modules/hardware/smart.nix;
    ups = ../modules/hardware/ups.nix;
    usb = ../modules/hardware/usb.nix;
    webcam = ../modules/hardware/webcam.nix;

    # Background services
    printing = ../modules/services/printing.nix;
    ssh = ../modules/services/ssh.nix;
    tailscale = ../modules/services/tailscale.nix;
    headscale = ../modules/services/headscale.nix;
    monitoring = ../modules/services/monitoring.nix;
    alerting = ../modules/services/alerting.nix;
    notify = ../modules/services/notify.nix;
    ntfy = ../modules/services/ntfy.nix;
    grafana = ../modules/services/grafana.nix;
    victoriametrics = ../modules/services/victoriametrics.nix;
    victorialogs = ../modules/services/victorialogs.nix;
    scrutiny = ../modules/services/scrutiny.nix;
    wireguard = ../modules/services/wireguard.nix;
    ddns = ../modules/services/ddns.nix;
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
    shell = ../modules/system/shell;
    bash = ../modules/system/shell/bash.nix;
    zsh = ../modules/system/shell/zsh.nix;
    starship = ../modules/system/shell/starship.nix;
  };
}
