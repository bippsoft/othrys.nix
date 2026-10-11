# flake/checks/pairs.nix
# CORE. The assertions that take two modules, or two options, to fire. Every
# other fixture enables a combination that evaluates, and the enable matrix
# turns one option on at a time, so an assertion about a pair is reached by
# neither. One whose condition is inverted, or whose guard no longer holds,
# stays silent on exactly the hosts it was written for. Each conflict is
# enabled here on a host that holds the pair and little else, and the failing
# assertion is matched by a fragment of its message.
#
# A module that requires another is read the same way. Those are grouped on
# one host where the requirement is shared, since each fragment names its own
# module.
#
# Pairs that another file already reads are left to it: rootful Docker on a
# router (./containers-eval.nix), Headscale beside Scrutiny, CrowdSec and the
# docs server (./headscale-eval.nix), the insecure Traefik dashboard beside a
# Headscale on another port (./services-eval.nix), k3s beside Traefik
# (./k3s-eval.nix), the router's Suricata hook (./router-services.nix), PRIME
# without the driver (./hardware-eval.nix), autologin without a lock path
# (./login.nix), the bootloader types under secureBoot (./bootloader.nix), and
# the requirements the enable matrix names by message (./enable-matrix.nix).
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
}: let
  nix = {
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
  };
  headless = extra: hostConfig [bootBase nix extra];
  workstation = extra: hostConfig [functioningHost extra];

  # Conflicts.

  # Podman's docker alias beside a rootful Docker daemon. The rootless
  # daemon is a user service and leaves virtualisation.docker.enable off.
  dockerBesidePodman = workstation {
    othrys.services.containerization = {
      docker = {
        enable = true;
        rootless.enable = false;
      };
      podman.enable = true;
    };
  };

  # The default, rootless Docker also installs a `docker` command, with
  # virtualisation.docker.enable left off.
  rootlessDockerBesidePodman = workstation {
    othrys.services.containerization = {
      docker.enable = true;
      podman.enable = true;
    };
  };

  # The NVIDIA container runtime on the default rootless daemon, on a host
  # without the driver. Both of Docker's NVIDIA assertions fire here.
  dockerNvidia = workstation {
    othrys.services.containerization.docker = {
      enable = true;
      nvidia.enable = true;
    };
  };

  scrutinyBesideCrowdsec = headless {
    othrys.services.scrutiny.enable = true;
    othrys.services.security.crowdsec = {
      enable = true;
      collections = [];
    };
  };

  # Traefik's insecure dashboard binds 8080, the default of three other
  # services.
  insecureDashboard = {
    othrys.services.traefik = {
      enable = true;
      dashboard = {
        enable = true;
        insecure = true;
      };
    };
  };
  dashboardBesideScrutiny = headless {
    imports = [insecureDashboard];
    othrys.services.scrutiny.enable = true;
  };
  dashboardBesideHeadscale = headless {
    imports = [insecureDashboard];
    othrys.services.headscale = {
      enable = true;
      serverUrl = "https://hs.example.com";
      baseDomain = "tail.example.com";
      nameservers = ["192.0.2.53"];
    };
  };
  dashboardBesideCrowdsec = headless {
    imports = [insecureDashboard];
    othrys.services.security.crowdsec = {
      enable = true;
      collections = [];
    };
  };
  # The same pair with the dashboard's entrypoint moved by the host.
  dashboardMoved = headless {
    imports = [insecureDashboard];
    othrys.services.traefik.staticConfigOptions.entryPoints.traefik.address = "127.0.0.1:8090";
    othrys.services.scrutiny.enable = true;
  };

  primeWithoutIntel = workstation {
    othrys.system.nix.allowUnfree = true;
    othrys.hardware.nvidia = {
      enable = true;
      blacklistIntel = true;
      prime = {
        enable = true;
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };
  };

  routerBesideFirewall = headless {
    othrys.services.firewall.enable = true;
    othrys.services.router = {
      enable = true;
      wan.interface = "wan0";
      lan.interfaces = ["lan0"];
    };
  };

  bothIdentities = headless {
    othrys.system.secrets = {
      enable = true;
      ageIdentityStubs = "AGE-PLUGIN-YUBIKEY-1EXAMPLE";
      ageIdentityFile = "/run/secrets/sops/age-identity";
    };
  };

  bothUpgradeSources = workstation {
    othrys.system.autoUpgrade = {
      enable = true;
      flake = "github:example/fleet";
      verify = {
        enable = true;
        url = "https://example.com/alice/hosts.git";
        publicKeys = ["/run/signers/alice.asc"];
      };
    };
  };

  # The kernel module writes boot.kernelPackages as a plain definition, and
  # the option takes one definition. A host that assigns it as well is
  # refused by the module system and not by an assertion, so there is no
  # message in config.assertions to match and the failure is caught instead.
  kernelAlone = headless {othrys.system.kernel.enable = true;};
  kernelTwice = headless ({pkgs, ...}: {
    othrys.system.kernel.enable = true;
    boot.kernelPackages = pkgs.linuxPackages;
  });
  kernelMerges = cfg: (builtins.tryEval (builtins.seq cfg.boot.kernelPackages true)).success;

  # Requirements.

  # Five modules that read the Stylix palette, on a host without it.
  unthemed = workstation {
    othrys.apps.floorp.enable = true;
    othrys.apps.gaming.mangohud.enable = true;
    othrys.desktop.compositors.hyprland.enable = true;
    othrys.desktop.compositors.niri.enable = true;
    othrys.system.shell.starship.enable = true;
  };

  # Three desktop modules on a host with no compositor and no graphical flag.
  noSession = workstation {
    othrys.system.stylix.enable = true;
    othrys.desktop.ashell.enable = true;
    othrys.desktop.idle.enable = true;
    othrys.desktop.nightLight = {
      enable = true;
      latitude = 0.0;
      longitude = 0.0;
    };
  };

  neovimWithoutNixvim = workstation {
    othrys.apps.vscode = {
      enable = true;
      neovimIntegration.enable = true;
    };
  };

  # Autologin starts the session as the primary user, on a host that names
  # one and manages no account.
  autoLoginNoAccount = headless {
    othrys.desktop.login = {
      enable = true;
      autoLogin = true;
      sessionCommand = "example-session";
    };
  };

  # The secrets module on an impermanence host that neither persists the ssh
  # host key nor runs sshd. disko.enableConfig = false keeps disko from
  # emitting filesystems that collide with the fixture's own, so the two
  # volumes impermanence marks as needed for boot are named.
  secretsWithoutHostKey = headless {
    disko.enableConfig = false;
    fileSystems = {
      "/nix" = {
        device = "/dev/disk/by-label/nix";
        fsType = "btrfs";
      };
      "/persist" = {
        device = "/dev/disk/by-label/persist";
        fsType = "btrfs";
      };
    };
    othrys.system = {
      disko = {
        enable = true;
        device = "/dev/disk/by-id/example";
      };
      impermanence.enable = true;
      secrets.enable = true;
    };
  };

  # Alerting with a datasource and nowhere to deliver.
  alertingWithoutDelivery = headless {
    othrys.services.victoriametrics.enable = true;
    othrys.services.alerting.enable = true;
  };
in
  mkExpectations "othrys-eval-pairs" {
    "podman's docker alias beside a rootful docker daemon is rejected" = rejectedWith "Podman dockerCompat conflicts" dockerBesidePodman;
    "podman's docker alias beside rootless docker is rejected" = rejectedWith "Podman dockerCompat conflicts" rootlessDockerBesidePodman;
    "the NVIDIA runtime on rootless docker is rejected" = rejectedWith "Docker rootless mode is incompatible" dockerNvidia;
    "the NVIDIA runtime without the driver is rejected" = rejectedWith "Docker NVIDIA support requires" dockerNvidia;
    "scrutiny beside crowdsec on port 8080 is rejected" = rejectedWith "Give Scrutiny another port" scrutinyBesideCrowdsec;
    "the insecure dashboard beside scrutiny on port 8080 is rejected" = rejectedWith "which is also othrys.services.scrutiny.port" dashboardBesideScrutiny;
    "the insecure dashboard beside headscale on port 8080 is rejected" = rejectedWith "which is also othrys.services.headscale.port" dashboardBesideHeadscale;
    "the insecure dashboard beside crowdsec is rejected" = rejectedWith "dashboard.insecure serves the dashboard on port 8080, which is where the CrowdSec local API" dashboardBesideCrowdsec;
    "a dashboard entrypoint the host moved is accepted" = !rejectedWith "dashboard.insecure serves the dashboard" dashboardMoved;
    "blacklistIntel beside PRIME is rejected" = rejectedWith "blacklistIntel removes the i915 driver" primeWithoutIntel;
    "the router beside the firewall module is rejected" = rejectedWith "do not also enable othrys.services.firewall" routerBesideFirewall;
    "an identity stub beside an identity file is rejected" = rejectedWith "set ageIdentityStubs or ageIdentityFile, not both" bothIdentities;
    "a flake beside the verify gate is rejected" = rejectedWith "set exactly one upgrade source" bothUpgradeSources;
    "the kernel module alone sets boot.kernelPackages" = kernelMerges kernelAlone;
    "a host assignment of boot.kernelPackages beside the kernel module is refused" = !kernelMerges kernelTwice;

    "floorp without stylix is rejected" = rejectedWith "othrys.apps.floorp requires othrys.system.stylix.enable" unthemed;
    "mangohud without stylix is rejected" = rejectedWith "othrys.apps.gaming.mangohud requires othrys.system.stylix.enable" unthemed;
    "hyprland without stylix is rejected" = rejectedWith "othrys.desktop.compositors.hyprland requires othrys.system.stylix.enable" unthemed;
    "niri without stylix is rejected" = rejectedWith "othrys.desktop.compositors.niri requires othrys.system.stylix.enable" unthemed;
    "starship without stylix is rejected" = rejectedWith "othrys.system.shell.starship requires othrys.system.stylix.enable" unthemed;
    "idle without a graphical session is rejected" = rejectedWith "othrys.desktop.idle requires a graphical session" noSession;
    "the night light without a graphical session is rejected" = rejectedWith "othrys.desktop.nightLight requires a graphical session" noSession;
    "ashell without a compositor is rejected" = rejectedWith "othrys.desktop.ashell requires a supported compositor" noSession;
    "neovim integration without nixvim is rejected" = rejectedWith "neovimIntegration.enable requires othrys.apps.nixvim.enable" neovimWithoutNixvim;
    "autologin without a managed account is rejected" = rejectedWith "needs othrys.system.users.enable" autoLoginNoAccount;
    "secrets on an impermanence host without the persisted host key are rejected" = rejectedWith "exists only with othrys.system.persistence.enable" secretsWithoutHostKey;
    "alerting without a delivery path is rejected" = rejectedWith "othrys.services.alerting: no delivery path" alertingWithoutDelivery;
  }
