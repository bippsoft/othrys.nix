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
# `default` leaves four exports out, since each writes into the option
# namespace of an upstream flake that a host may not use. `stylix` is the
# adapter between othrys.theme and Stylix, `disko` is the disk layout,
# `secrets` is the sops-nix plumbing and `impermanence` hands the persistence
# registry to the impermanence module. A host imports each together with the
# upstream module it configures, or imports neither.
#
# Rule when adding a module. If it lives outside modules/apps/, add an
# individual export here. The `eval-exports` check (flake/checks/) lists the
# tree and fails when a module file is missing from this list or an export
# points at a file that no longer exists.
#
# An individual export is one file, and most of them read options declared
# in other files. The primary user and the home-manager registry come from
# system/user.nix and system/users.nix, the persist root from
# system/ephemeral-root.nix, the persistence registry from
# system/persistence.nix, the default editor from system/shell, the
# graphical signal from desktop/default.nix and the notification hook from
# services/notify.nix. The palette and fonts come from theme/default.nix.
# Import `system` beside any individual export, `theme` beside one that draws
# colour, and `desktop` beside a desktop or hardware one, or use `default`.
#
# Six exports are wrapped in `withArgs` below, which are `system`, `desktop`,
# `nix`, `secrets`, `hyprland` and `ashell`. Their files take the
# `othrysInputs` or `inputs` module argument, and the wrapper supplies it.
#
# `default` writes into one option namespace owned by an upstream flake,
# which is home-manager. A consumer of `default` must also import that
# flake's nixosModule, see docs/src/architecture/host-configuration.md. This
# holds even when no othrys module configures the user.
#
# Usage from another flake:
#   inputs.othrys.nixosModules.default
#   inputs.othrys.nixosModules.system
#   inputs.othrys.nixosModules.tailscale
{inputs, ...}: let
  # What the modules take from this flake's own lock, as module arguments.
  # A module can only reach flake inputs through an argument, and reading them
  # from the consumer's `inputs` made every consuming flake declare an input
  # named `ashell`, `hyprland`, `nixvim` and `nix-index-database`. Only the
  # four the modules use are named, so a module cannot grow a dependency on
  # another input unnoticed.
  #
  # `inputs` is given an empty default beside them. modules/system/nix.nix
  # reads the consumer's `inputs.nixpkgs` and modules/system/secrets.nix the
  # consumer's optional `inputs.secrets`, both through specialArgs, and a
  # consumer who passes no specialArgs would otherwise fail on the missing
  # argument before either `or` fallback is reached. A specialArg of the same
  # name takes precedence over this default.
  #
  # The `key` makes the module system keep one copy when a host imports
  # several exports that carry this module.
  args = {
    key = "othrys.nix/flake/modules.nix#args";
    _module.args = {
      othrysInputs = {inherit (inputs) ashell hyprland nixvim nix-index-database;};
      inputs = inputs.nixpkgs.lib.mkDefault {};
    };
  };

  # An individual export whose file, or a file below it, takes `othrysInputs`
  # or `inputs`. `default` is not on the import path of an individual export,
  # so the export carries the arguments itself.
  withArgs = path: {imports = [args path];};
in {
  flake.nixosModules = {
    # Aggregate of the full module tree. Injects this flake's own source as the
    # `othrysSelf` module arg for modules that build from it (services/docs.nix),
    # so consumers don't need to thread it through specialArgs.
    #
    # niri-flake's module is imported here and not inside the tree. An import
    # is evaluated on every host, and a module argument cannot be read in
    # `imports`, so importing it from modules/ made every consumer declare a
    # niri input whether or not they used niri. Here it comes from this
    # flake's own lock.
    default = {
      imports = [
        args
        ../modules
        inputs.niri.nixosModules.niri
      ];
      _module.args.othrysSelf = inputs.self;
    };

    # The option-declaring groups, imported beside an individual export.
    system = withArgs ../modules/system;
    theme = ../modules/theme;
    desktop = withArgs ../modules/desktop;

    # The Stylix adapter, which `default` does not import. A host that wants
    # Stylix imports this and the Stylix module together.
    stylix = ../modules/theme/stylix.nix;

    # The disk layout and the sops-nix plumbing, which `default` and `system`
    # do not import either. A host that wants the layout imports `disko` and
    # the disko module together, and one that wants the plumbing imports
    # `secrets` and the sops-nix module together. Both read options the
    # `system` group declares.
    disko = ../modules/system/disko.nix;
    secrets = withArgs ../modules/system/secrets.nix;

    # The impermanence adapter, left out of `default` and `system` on the same
    # terms. A host with an ephemeral root imports this and the impermanence
    # module together. The options it reads and the root wipe are in
    # `ephemeral-root`, and the registry it reads is in `persistence`, both
    # part of `system`.
    impermanence = ../modules/system/impermanence.nix;

    # System fundamentals
    locale = ../modules/system/locale.nix;
    user = ../modules/system/user.nix;
    users = ../modules/system/users.nix;
    nix = withArgs ../modules/system/nix.nix;
    kernel = ../modules/system/kernel.nix;
    hardening = ../modules/system/hardening.nix;
    networking = ../modules/system/networking.nix;
    ephemeral-root = ../modules/system/ephemeral-root.nix;
    persistence = ../modules/system/persistence.nix;
    bootloader = ../modules/system/bootloader.nix;
    git = ../modules/system/git.nix;
    auto-upgrade = ../modules/system/auto-upgrade.nix;

    # Desktop environment and compositors
    hyprland = withArgs ../modules/desktop/compositors/hyprland.nix;
    niri = ../modules/desktop/compositors/niri.nix;
    uwsm = ../modules/desktop/uwsm.nix;
    login = ../modules/desktop/login.nix;
    idle = ../modules/desktop/idle.nix;
    night-light = ../modules/desktop/night-light.nix;
    keyring = ../modules/desktop/keyring.nix;
    wallpaper = ../modules/desktop/wallpaper.nix;
    ashell = withArgs ../modules/desktop/ashell;

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
