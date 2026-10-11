# flake/checks/k3s-eval.nix
# CORE. What the k3s module opens and requires, read back from evaluated
# hosts. The firewall opened the API, etcd and the kubelet on every interface
# by default, a plaintext token option sat beside the file one, and a server
# beside the Traefik module bound 80 and 443 twice. None of that fails
# evaluation on its own. The same goes for the flags a server starts with, the
# forwarding sysctl written under two names, and a package option whose
# default the reference showed as null.
{
  hostConfig,
  impermanenceModules,
  hostEval,
  mkExpectations,
  rejectedWith,
  bootBase,
}: let
  modules = extra: [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
      othrys.system.nix.allowUnfree = true;
    }
    extra
  ];
  host = extra: hostConfig (modules extra);
  k3s = extra: host {othrys.services.containerization.k3s = {enable = true;} // extra;};
  fw = cfg: cfg.networking.firewall;

  single = k3s {};
  singleOpen = k3s {openFirewall = true;};
  initOpen = k3s {
    openFirewall = true;
    clusterInit = true;
  };
  agent = k3s {
    role = "agent";
    serverAddr = "https://192.0.2.1:6443";
  };
  agentWithToken = k3s {
    role = "agent";
    serverAddr = "https://192.0.2.1:6443";
    tokenFile = "/run/secrets/k3s-token";
  };
  joiningServer = k3s {serverAddr = "https://192.0.2.1:6443";};
  hardened = ["--write-kubeconfig-mode=0600" "--secrets-encryption"];
  withFlag = k3s {extraFlags = ["--flannel-backend=wireguard-native"];};
  unhardened = k3s {
    hardenedFlags = false;
    extraFlags = ["--flannel-backend=wireguard-native"];
  };
  onRouter = host {
    othrys.services.containerization.k3s.enable = true;
    othrys.services.router = {
      enable = true;
      wan.interface = "wan0";
      lan.interfaces = ["lan0"];
    };
  };
  sysctl = cfg: cfg.boot.kernel.sysctl;
  # A defaultText is read from the option, which the config does not carry.
  packageOption = (hostEval (modules {})).options.othrys.services.containerization.k3s.package;
  besideTraefik = host {
    othrys.services.containerization.k3s.enable = true;
    othrys.services.traefik.enable = true;
  };
  besideTraefikDisabled = host {
    othrys.services.containerization.k3s = {
      enable = true;
      disable = ["traefik"];
    };
    othrys.services.traefik.enable = true;
  };
  rancherDirs =
    (host {
      imports = [impermanenceModules];
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
        impermanence = {
          enable = true;
          device = "/dev/disk/by-partlabel/root";
        };
      };
      othrys.services.containerization.k3s.enable = true;
    }).environment.persistence."/persist".directories;
in
  mkExpectations "othrys-eval-k3s" {
    "nothing is opened by default" = !builtins.elem 6443 (fw single).allowedTCPPorts && !builtins.elem 8472 (fw single).allowedUDPPorts;
    "a single server opens the API and the kubelet when asked" = builtins.elem 6443 (fw singleOpen).allowedTCPPorts && builtins.elem 10250 (fw singleOpen).allowedTCPPorts && builtins.elem 8472 (fw singleOpen).allowedUDPPorts;
    "a single server keeps etcd closed" = !builtins.elem 2379 (fw singleOpen).allowedTCPPorts && !builtins.elem 2380 (fw singleOpen).allowedTCPPorts;
    "a server that initialises a cluster opens etcd" = builtins.elem 2379 (fw initOpen).allowedTCPPorts && builtins.elem 2380 (fw initOpen).allowedTCPPorts;
    "an agent without a token file is rejected" = rejectedWith "set tokenFile" agent;
    "an agent with a token file is accepted" = !rejectedWith "tokenFile" agentWithToken;
    "a server joining another without a token file is rejected" = rejectedWith "set tokenFile" joiningServer;
    "a server beside the Traefik module is rejected" = rejectedWith "bundles its own Traefik" besideTraefik;
    "a server with its Traefik disabled beside the module is accepted" = !rejectedWith "Traefik" besideTraefikDisabled;
    "a server starts with the hardened flags" = single.services.k3s.extraFlags == hardened;
    "a host's own flags follow the hardened ones" = withFlag.services.k3s.extraFlags == hardened ++ ["--flannel-backend=wireguard-native"];
    "hardenedFlags = false leaves the host's flags alone" = unhardened.services.k3s.extraFlags == ["--flannel-backend=wireguard-native"];
    "an agent takes neither server flag" = agentWithToken.services.k3s.extraFlags == [];
    "forwarding is written under one key" = (sysctl single)."net.ipv4.conf.all.forwarding" == true && !((sysctl single) ? "net.ipv4.ip_forward");
    "a router beside k3s still writes forwarding once" = (sysctl onRouter)."net.ipv4.conf.all.forwarding" == 1 && !((sysctl onRouter) ? "net.ipv4.ip_forward");
    "the package option documents its default" = packageOption.defaultText.text == "pkgs.k3s";
    "the rancher directory is persisted private to root" = builtins.any (d: d.directory or "" == "/etc/rancher" && d.mode == "0700") rancherDirs;
  }
