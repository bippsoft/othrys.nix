# Containerization

Container modules under `othrys.services.containerization.*`. Located in `modules/services/containerization/`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Podman | `othrys.services.containerization.podman` | Container runtime with Docker compatibility |
| Docker | `othrys.services.containerization.docker` | Docker runtime (conflicts with Podman dockerCompat) |
| k3s | `othrys.services.containerization.k3s` | Lightweight single-node/cluster Kubernetes |

## Podman

### Options

```nix
{{#include ../../../modules/services/containerization/podman.nix:podman-options}}
```

### Features

- Docker CLI compatibility via `dockerCompat`
- DNS enabled for container networking (required for compose)
- Weekly auto-prune of unused images
- podman-compose for docker-compose compatibility
- Optional Distrobox for running containers as native apps
- Shell aliases: `docker-compose` → `podman-compose`

The primary user runs podman rootless and is not added to group `podman`.
That group owns the rootful `podman.socket` nixpkgs installs, so membership is
access to the root daemon's API, which is root. A host that wants a user on
the rootful socket adds the group in `users.users.<name>.extraGroups` itself.
- Persistence for container storage and config

## Docker

The Docker runtime (`othrys.services.containerization.docker`), rootless by
default. With `rootless.enable` the only daemon is the user's, started in the
user's session, and no rootful daemon or root socket runs; the user's store is
pruned by a user timer on `autoPrune.dates`. With `rootless.enable = false`
the rootful daemon runs, the primary user joins group `docker`, and upstream's
prune unit prunes the root store. That group owns the root daemon's socket, so
membership is root.

The rootful daemon writes its own iptables rules ahead of the router's chain,
so on a host with `othrys.services.router` a published container port is
reachable from the WAN whatever the router allows. The module refuses that
pairing unless `daemon.settings.iptables = false` is set, after which ports
are published through the router's `portForwards`. Rootless Docker reaches the
network through its own namespace and touches no host rules.

## k3s

Lightweight Kubernetes (`othrys.services.containerization.k3s`) for a single-node
control plane or a joined cluster. See `modules/services/containerization/k3s.nix`
for the full option set (role, node labels and taints, manifests).

The cluster token is a file from the secrets provider, `tokenFile`, and never
a string in the configuration. An agent, or a server that joins another through
`serverAddr`, must set it; a single server that initialises its own cluster
needs none. `openFirewall` is off by default. On, it opens the kubelet and the
flannel tunnel on every node, the API on a server, and embedded etcd only on a
server that initialises or joins a cluster. k3s bundles its own Traefik on 80
and 443, so a server beside `othrys.services.traefik` must list `"traefik"` in
`disable`. `/etc/rancher`, which holds the admin kubeconfig, is persisted
private to root.
