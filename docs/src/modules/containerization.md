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

## k3s

Lightweight Kubernetes (`othrys.services.containerization.k3s`) for a single-node
control plane or a joined cluster. See `modules/services/containerization/k3s.nix`
for the full option set (role, token/secret wiring, and firewall handling).
