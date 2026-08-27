# modules/services/containerization/k3s.nix
# k3s, lightweight Kubernetes (single-node, HA server, or agent)
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.containerization.k3s;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
  isServer = cfg.role == "server";
in {
  options.othrys.services.containerization.k3s = {
    enable = lib.mkEnableOption "k3s lightweight Kubernetes";

    role = lib.mkOption {
      type = lib.types.enum ["server" "agent"];
      default = "server";
      description = "Whether this node runs the control plane (server) or joins as a worker (agent).";
    };

    clusterInit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Initialize a highly-available cluster with an embedded etcd datastore.
        Set on the first server only; further servers join it via serverAddr.
      '';
    };

    serverAddr = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "https://10.0.0.1:6443";
      description = "URL of the server to join. Required for agents and for additional HA servers.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = lib.literalExpression ''config.sops.secrets."k3s/token".path'';
      description = "Path to the cluster join token. Preferred over `token` (kept out of the store).";
    };

    token = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Cluster join token as plaintext.
        WARNING: world-readable in the Nix store, so prefer `tokenFile`.
      '';
    };

    disable = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["traefik" "servicelb"];
      description = "Bundled components to disable (e.g. to bring your own ingress/LB).";
    };

    disableAgent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Server only: run the control plane without scheduling workloads on this node.";
    };

    nodeName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override the node name (defaults to the hostname).";
    };

    nodeLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["node-role=worker"];
      description = "Labels to register the kubelet with.";
    };

    nodeTaints = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["CriticalAddonsOnly=true:NoExecute"];
      description = "Taints to register the kubelet with.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--flannel-backend=wireguard-native"];
      description = "Extra flags appended to the k3s command.";
    };

    manifests = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Auto-deploying manifests (forwarded to services.k3s.manifests). Server only.";
    };

    extraKubeletConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Extra kubelet configuration (forwarded to services.k3s.extraKubeletConfig).";
    };

    gracefulShutdown = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Drain pods gracefully when the node shuts down.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the k3s API/kubelet/flannel ports in the firewall.";
    };

    installTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install cluster tooling (kubectl, helm, k9s) system-wide.";
    };

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Override the k3s package (e.g. to pin a Kubernetes version).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.token != null && cfg.tokenFile != null);
        message = "othrys.services.containerization.k3s: set either token or tokenFile, not both.";
      }
      {
        assertion = isServer || cfg.serverAddr != "";
        message = "othrys.services.containerization.k3s: role = \"agent\" requires serverAddr (the server URL to join).";
      }
    ];

    # Pod networking prerequisites.
    boot.kernelModules = ["br_netfilter" "overlay"];
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };

    services.k3s = {
      enable = true;
      inherit (cfg) role clusterInit serverAddr disable disableAgent extraFlags manifests extraKubeletConfig tokenFile nodeName;
      token = lib.mkIf (cfg.token != null) cfg.token;
      package = lib.mkIf (cfg.package != null) cfg.package;
      nodeLabel = cfg.nodeLabels;
      nodeTaint = cfg.nodeTaints;
      gracefulNodeShutdown.enable = cfg.gracefulShutdown;
    };

    # Servers expose the API (6443) and embedded etcd (2379/2380 for HA);
    # every node needs the kubelet port and the flannel VXLAN tunnel.
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts =
        [10250]
        ++ lib.optionals isServer [6443 2379 2380];
      allowedUDPPorts = [8472];
    };

    # Point root's kubectl at the generated admin kubeconfig.
    environment.variables = lib.mkIf isServer {
      KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    };

    environment.systemPackages = lib.optionals cfg.installTools (with pkgs; [
      kubectl
      kubernetes-helm
      k9s
    ]);

    # Cluster state must survive reboots under impermanence.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      directories = [
        {
          directory = "/var/lib/rancher/k3s";
          user = "root";
          group = "root";
          mode = "0700";
        }
        "/etc/rancher"
      ];
    };
  };
}
