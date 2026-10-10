# flake/checks/containers-eval.nix
# CORE. What the two container modules run and prune, read back from
# evaluated hosts. A rootless Docker host once ran a rootful daemon beside the
# user's, with a root socket for the docker group and a prune unit that never
# reached the user's store, and nothing in that fails evaluation.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
}: let
  host = extra: hostConfig [functioningHost extra];

  rootless = host {othrys.services.containerization.docker.enable = true;};
  rootful = host {
    othrys.services.containerization.docker = {
      enable = true;
      rootless.enable = false;
    };
  };
  rootfulOnRouter = host {
    othrys.services.containerization.docker = {
      enable = true;
      rootless.enable = false;
    };
    othrys.services.router = {
      enable = true;
      wan.interface = "wan0";
      lan.interfaces = ["lan0"];
    };
  };
  rootfulOnRouterNoIptables = host {
    othrys.services.containerization.docker = {
      enable = true;
      rootless.enable = false;
      daemon.settings.iptables = false;
    };
    othrys.services.router = {
      enable = true;
      wan.interface = "wan0";
      lan.interfaces = ["lan0"];
    };
  };
  rootlessOnRouter = host {
    othrys.services.containerization.docker.enable = true;
    othrys.services.router = {
      enable = true;
      wan.interface = "wan0";
      lan.interfaces = ["lan0"];
    };
  };
  podman = host {othrys.services.containerization.podman.enable = true;};

  user = rootless.othrys.system.user.name;
  groups = cfg: cfg.users.users.${user}.extraGroups;
in
  mkExpectations "othrys-eval-containers" {
    "rootless docker runs no rootful daemon" = !rootless.virtualisation.docker.enable && rootless.virtualisation.docker.rootless.enable;
    "rootless docker gives the user no docker group" = !builtins.elem "docker" (groups rootless);
    "rootless docker prunes from a user timer on the user's socket" = rootless.systemd.user.services.docker-prune.environment.DOCKER_HOST == "unix://%t/docker.sock" && rootless.systemd.user.timers.docker-prune.timerConfig.OnCalendar == "weekly";
    "rootless docker turns the rootful prune off" = !rootless.virtualisation.docker.autoPrune.enable;
    "rootful docker runs the rootful daemon with its prune" = rootful.virtualisation.docker.enable && rootful.virtualisation.docker.autoPrune.enable;
    "rootful docker puts the user in the docker group" = builtins.elem "docker" (groups rootful);
    "rootful docker renders no user prune" = !(rootful.systemd.user.services ? docker-prune);
    "rootful docker on a router is refused while it manages iptables" = rejectedWith "ahead of the router's chain" rootfulOnRouter;
    "rootful docker on a router is accepted with iptables off" = !rejectedWith "router" rootfulOnRouterNoIptables;
    "rootless docker on a router is accepted" = !rejectedWith "router" rootlessOnRouter;
    "podman prunes the user's store from a user timer" = podman.systemd.user.services.podman-prune.unitConfig.ConditionPathExists == "%h/.local/share/containers" && podman.systemd.user.timers.podman-prune.timerConfig.OnCalendar == "weekly";
    "podman keeps the user out of its group" = !builtins.elem "podman" (groups podman);
  }
