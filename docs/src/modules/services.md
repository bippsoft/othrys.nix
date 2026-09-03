# Services

Service modules under `othrys.services.*`.

## Available Modules

| Module | Option | Description |
|--------|--------|-------------|
| Docs | `othrys.services.docs` | MdBook documentation server (darkhttpd) |
| SSH | `othrys.services.ssh` | OpenSSH server |
| Tailscale | `othrys.services.tailscale` | VPN mesh network |
| WireGuard | `othrys.services.wireguard` | Raw WireGuard interfaces (site-to-site, exit nodes) |
| DDNS | `othrys.services.ddns` | Dynamic DNS updates (inadyn) |
| Headscale | `othrys.services.headscale` | Self-hosted Tailscale control server |
| Monitoring | `othrys.services.monitoring` | System monitoring tools |
| VictoriaMetrics | `othrys.services.victoriametrics` | Time-series database (Prometheus-compatible) |
| VictoriaLogs | `othrys.services.victorialogs` | Log database (LogsQL, journald ingestion) |
| Grafana | `othrys.services.grafana` | Dashboards (datasources auto-provisioned) |
| Alerting | `othrys.services.alerting` | vmalert rule evaluation with ntfy delivery |
| Ntfy | `othrys.services.ntfy` | Self-hosted push-notification server |
| Notify | `othrys.services.notify` | Host notification dispatch + failure hooks |
| Automount | `othrys.services.automount` | USB automounting |
| Firewall | `othrys.services.firewall` | Firewall configuration |
| Router | `othrys.services.router` | L3 router firewall + NAT (nftables), optional NFQUEUE hook |
| Suricata | `othrys.services.suricata` | IDS/IPS (NFQUEUE or AF_PACKET inline) |
| Kea | `othrys.services.kea` | Kea DHCPv4/DHCPv6 server |
| Unbound | `othrys.services.unbound` | Recursive DNS (DoT upstream, RPZ blocklists) |
| Restic | `othrys.services.restic` | Scheduled restic backups (secrets via file paths) |
| Virtual Camera | `othrys.services.virtualcamera` | Virtual camera support |
| Printing | `othrys.services.printing` | CUPS printing |
| Mounts (Disks) | `othrys.services.mounts.disks` | Additional disk mounts (NTFS, ext4, btrfs) |
| Mounts (CIFS) | `othrys.services.mounts.cifs` | CIFS/SMB network share mounts |

See also: [Security](./security.md), [Containerization](./containerization.md)

## Documentation Server

Builds the MdBook documentation at Nix evaluation time and serves it via darkhttpd.

### Options

```nix
{{#include ../../../modules/services/docs.nix:docs-options}}
```

### Usage

```nix
othrys.services.docs = {
  enable = true;
  port = 3000;             # default
  interface = "127.0.0.1"; # default, use "0.0.0.0" for all interfaces
  openFirewall = false;    # default
  desktopEntry = false;    # default, creates XDG desktop entry to open in browser
};
```

The docs are built from the flake source as a derivation, with no runtime build step. The built package is also accessible as `config.othrys.services.docs.package`.

When `desktopEntry` is enabled, an "othrys.nix Docs" entry appears in application launchers, opening the docs in the default browser via `xdg-open`.

## Router

An L3 router firewall + NAT built on `networking.nftables`. It generates a
default-drop `inet` filter (input/forward) and an `ip` masquerade from the WAN
and LAN interface options. LAN interfaces are trusted (input accepted, forwarded
to the WAN), while the WAN is default-drop except established/related. Interface names
and subnets are identity and come from the fleet host, and anything the generated
ruleset doesn't cover goes through `extraInputRules` / `extraForwardRules` /
`extraNat`.

With `suricata.enable`, forwarded traffic is handed to Suricata via NFQUEUE
(`queue num 0-<N-1> bypass`) instead of plain `accept`. Pair it with
`othrys.services.suricata` (`mode = "nfqueue"`, matching `nfqueue.queues`).
It disables `networking.firewall` (and asserts `othrys.services.firewall` is off).

Two separate mechanisms decide what happens when inspection stops, and they are
easy to confuse. The `bypass` flag above accepts packets when no process is bound
to the queue, so a dead or stopped Suricata does not take the link down, and it
is set unconditionally. `othrys.services.suricata.nfqueue.failOpen` covers the
other case, a running Suricata whose queue is full. Setting `failOpen = false`
therefore does not make a dead Suricata block traffic.

Both directions fail open on purpose, since an IPS crash on a router should not
sever the network it protects. The consequence is worth stating plainly: while
Suricata is down, forwarded traffic is uninspected rather than blocked, so the
link stays up with no IPS behind it.

### Options

```nix
{{#include ../../../modules/services/router.nix:router-options}}
```

### Usage

```nix
othrys.services.router = {
  enable = true;
  wan.interface = "enp1s0f0";
  lan.interfaces = ["br-lan"];
  nat.enable = true;          # IPv4 masquerade
  # Inline IPS: feed forwarded traffic to Suricata's NFQUEUE
  suricata = { enable = true; queues = 4; };
  # Raw escape hatches for port-forwards / policy:
  extraNat = "iifname \"enp1s0f0\" tcp dport 25565 dnat to 10.0.0.42:25565";
};
```

## Suricata

[Suricata](https://suricata.io/) IDS/IPS, wrapping the upstream
`services.suricata`. Two inline deliveries via `mode`:

- **`nfqueue`** (default) keeps the box an L3 router/NAT, since an nftables `queue`
  rule (the router/firewall module's job) hands packets to Suricata, which the
  module runs in NFQUEUE runmode. `nfqueue.queues` sets `-q 0 … -q N-1`, and
  `nfqueue.failOpen` accepts packets when a running Suricata's queue is full.
- **`af-packet`** captures on an interface; `posture = "ips"` builds a
  transparent L2 bridge across `afPacket.interface` + `afPacket.copyInterface`.

`posture` (`ids`/`ips`) selects alert-only against drop. Start in IDS, tune, then
flip. `offloadInterfaces` disables GRO/GSO/TSO/LRO (required for inline
correctness). Rules come from `enabledSources` (default `et/open`) via
`suricata-update`; deep tuning (threading/CPU-affinity, `mpm-algo = "hs"`,
outputs) goes through `settings`. Host-specific values (interface names,
isolcpus, core sets) stay in the fleet.

### Options

```nix
{{#include ../../../modules/services/suricata.nix:suricata-options}}
```

### Usage

```nix
# Router (NFQUEUE), start in IDS and feed it from nftables (`… queue num 0-3`)
othrys.services.suricata = {
  enable = true;
  mode = "nfqueue";          # default
  posture = "ids";           # alert-only until tuned
  nfqueue.queues = 4;
  offloadInterfaces = ["enp1s0f0" "enp1s0f1"];
  enabledSources = ["et/open"];
};

# Transparent bridge IPS (AF_PACKET)
othrys.services.suricata = {
  enable = true;
  mode = "af-packet";
  posture = "ips";
  afPacket = { interface = "enp1s0f0"; copyInterface = "enp1s0f1"; };
  offloadInterfaces = ["enp1s0f0" "enp1s0f1"];
};
```

## Kea

[Kea](https://kea.readthedocs.io/) DHCPv4/DHCPv6, a thin wrapper over
`services.kea` with sane defaults (bound interfaces + a persistent memfile lease
database). Subnets, reservations, and options are identity and come from the
fleet through `settings`, which is deep-merged over the defaults.

> **Gotcha (Kea 2.6+):** every subnet needs a unique mandatory `id`.

### Options

```nix
{{#include ../../../modules/services/kea.nix:kea-options}}
```

### Usage

```nix
othrys.services.kea = {
  enable = true;
  dhcp4 = {
    interfaces = ["br-lan"];
    settings.subnet4 = [{
      id = 1;
      subnet = "10.0.0.0/24";
      pools = [{ pool = "10.0.0.100 - 10.0.0.240"; }];
      option-data = [
        { name = "routers"; data = "10.0.0.1"; }
        { name = "domain-name-servers"; data = "10.0.0.1"; }
      ];
    }];
  };
};
```

## Unbound

[Unbound](https://nlnetlabs.nl/projects/unbound/) recursive DNS, a thin wrapper
over `services.unbound` with helpers for listen interfaces, per-subnet access
control, DNS-over-TLS upstream forwarding, and RPZ blocklists. Anything else
goes through `settings` (freeform unbound.conf), deep-merged over the generated
config.

### Options

```nix
{{#include ../../../modules/services/unbound.nix:unbound-options}}
```

### Usage

```nix
othrys.services.unbound = {
  enable = true;
  interfaces = ["10.0.0.1" "127.0.0.1"];
  accessControl = ["10.0.0.0/24 allow"];
  forwardTls.enable = true;   # DoT to Cloudflare + Quad9 by default
  rpz = [{
    name = "hagezi";
    url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/rpz/pro.txt";
  }];
};
```

## Restic

Scheduled [restic](https://restic.net/) backups, one entry per named backup
(maps to `services.restic.backups.<name>`). Every credential-bearing field is a
runtime **file path** sourced from a secrets provider (e.g. sops), never an
inline value or a `/nix/store` path. Use `passwordFile`, `repositoryFile`,
`environmentFile`, and `rcloneConfigFile`. Use plain `repository` only for
non-sensitive locations (a local disk path).

### Options

```nix
{{#include ../../../modules/services/restic.nix:restic-options}}
```

### Usage

```nix
othrys.services.restic.enable = true;
othrys.services.restic.backups.headscale = {
  paths = ["/var/lib/headscale"];
  # Repository URL and password come from sops (runtime files, not the store):
  repositoryFile = config.sops.secrets."backup/repo-url".path;
  passwordFile   = config.sops.secrets."backup/repo-password".path;
  # Backend credentials (S3/B2/SFTP key, etc.):
  environmentFile = config.sops.secrets."backup/env".path;

  timerConfig = { OnCalendar = "daily"; RandomizedDelaySec = "1h"; Persistent = true; };
  pruneOpts = ["--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6"];

  # Application-consistent snapshot (quiesce before, resume after):
  backupPrepareCommand = "systemctl stop myservice";
  backupCleanupCommand = "systemctl start myservice";
};
```

Secrets themselves are declared by the consuming fleet (via `othrys.system.secrets`
and sops), and this module only accepts the resulting file paths.

### Integrity checking

Plain `restic check` (what `runCheck` runs by default) verifies repository
**structure**, meaning index consistency and pack existence and size, but never reads
pack contents, so in-place bit corruption of backed-up data passes it
silently. Content verification requires `--read-data`, which downloads and
cryptographically verifies every pack. For repositories where a full read per
run is too expensive (remote backends, large repos), `--read-data-subset`
verifies a rotating fraction each run and still covers the whole repository
over time:

```nix
othrys.services.restic.backups.headscale = {
  # ...
  runCheck = true;
  # Verify a different 10% of pack data on each run, giving full coverage
  # roughly every 10 runs, at a tenth of the download cost:
  checkOpts = ["--read-data-subset=10%"];
};
```

On a fast local repository, `checkOpts = ["--read-data"]` buys full content
verification on every run.

## Headscale

[Headscale](https://headscale.net/) is a self-hosted implementation of the
Tailscale control server, the coordination plane the [Tailscale](#tailscale)
module points its `baseURL` at. A thin wrapper over `services.headscale` with
helpers for the public URL, listen socket, MagicDNS and OIDC, while anything else
goes through `settings` (freeform `config.yaml`), deep-merged over the generated
config. The OIDC client secret is a runtime **file path** from a secrets
provider, never an inline value.

An optional web UI ([Headplane](https://headplane.net/)) is bundled under `ui`.
Headplane was chosen over the static-SPA UIs (headscale-ui, headscale-admin) on
two axes: nixpkgs ships a native `services.headplane` module (no extra flake
input to carry), and it holds the Headscale API key, cookie secret, and OIDC
secret **server-side as file paths**, since the SPAs park a full-privilege API key in
browser `localStorage`. Enabling `ui` reuses this instance's generated config,
port, and user automatically, so you supply only the listen socket and a couple of
secret paths. OIDC SSO is the recommended (server-side-custody) login mode,
without it Headplane falls back to its in-browser API-key login.

### Options

```nix
{{#include ../../../modules/services/headscale.nix:headscale-options}}
```

### Usage

```nix
othrys.services.headscale = {
  enable = true;
  serverUrl = "https://headscale.example.com";  # public URL, behind a TLS reverse proxy
  baseDomain = "tailnet.example.com";            # MagicDNS suffix (must differ from serverUrl)
  nameservers = ["1.1.1.1" "9.9.9.9"];

  # Optional OIDC, client secret comes from sops (a runtime file, not the store):
  oidc = {
    enable = true;
    issuer = "https://auth.example.com/realms/main";
    clientId = "headscale";
    clientSecretFile = config.sops.secrets."headscale/oidc-secret".path;
  };

  # Optional Headplane web UI (server-side secret custody, OIDC SSO):
  ui = {
    enable = true;
    cookieSecretFile = config.sops.secrets."headscale/headplane-cookie".path;
    apiKeyFile       = config.sops.secrets."headscale/headplane-apikey".path; # `headscale apikeys create`
    oidc = {
      enable = true;
      issuer = "https://auth.example.com/realms/main";
      clientId = "headplane";
      clientSecretFile = config.sops.secrets."headscale/headplane-oidc".path;
    };
  };
};
```

Put a TLS-terminating reverse proxy in front of both Headscale (`serverUrl`) and
Headplane (which listens on `127.0.0.1:3000` by default); behind a proxy set
`ui.settings.server.base_url` to Headplane's public URL so OIDC redirects
resolve. A node then registers against this server by pointing the Tailscale
module at it:
`othrys.services.tailscale = { enable = true; baseURL = "https://headscale.example.com"; }`.

## Mounts

Non-system filesystem mounts, grouped under `othrys.services.mounts.*`.

### Disks

Additional local disk mounts (NTFS, ext4, btrfs, xfs, vfat).

#### Options

```nix
{{#include ../../../modules/services/mounts/disks.nix:disks-options}}
```

### CIFS

CIFS/SMB network share mounts. Credentials files are generated from sops templates containing username/password pairs.

#### Options

```nix
{{#include ../../../modules/services/mounts/cifs.nix:cifs-options}}
```

## VictoriaMetrics

[VictoriaMetrics](https://victoriametrics.com/) is a fast, resource-efficient
time-series database with a Prometheus-compatible API (scrape, remote-write,
MetricsQL). A thin wrapper over `services.victoriametrics`: loopback by default
(reverse proxy in front), retention exposed as policy, and an optional scrape
of the node exporter the [Monitoring](#monitoring) module runs, so enabling both
wires them together automatically.

### Options

```nix
{{#include ../../../modules/services/victoriametrics.nix:victoriametrics-options}}
```

### Usage

```nix
othrys.services.victoriametrics = {
  enable = true;
  retentionPeriod = "1y";
  scrapeConfigs = [
    {
      job_name = "headscale";
      static_configs = [{targets = ["127.0.0.1:9090"];}];
    }
  ];
};
```

## VictoriaLogs

[VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) is the log
database from the VictoriaMetrics family (LogsQL queries, minimal footprint).
The host's systemd journal ships to it natively via `systemd-journal-upload`
with no extra agent.

### Options

```nix
{{#include ../../../modules/services/victorialogs.nix:victorialogs-options}}
```

## Grafana

Dashboards over the othrys stores. Datasources are auto-provisioned from
whichever stores are enabled on the same host ([Monitoring](#monitoring)'s
Prometheus, [VictoriaMetrics](#victoriametrics), and
[VictoriaLogs](#victorialogs), the last with its datasource plugin
installed, since that type is not built into Grafana). Enabling Grafana
beside any of them wires them together with zero configuration. The admin
password arrives as a secrets-provider file path.

### Options

```nix
{{#include ../../../modules/services/grafana.nix:grafana-options}}
```

## Alerting

Rule evaluation via vmalert, datasource-agnostic (any Prometheus-compatible
API, with the local VictoriaMetrics or Prometheus auto-discovered). Delivery
flows to [Notify](#notify) through an internal alertmanager →
alertmanager-ntfy chain (loopback implementation details, while the consumer
surface is rules in, phone notifications out). Ships curated starter rules
(instance down, disk space, memory pressure) that can be disabled or
extended.

### Options

```nix
{{#include ../../../modules/services/alerting.nix:alerting-options}}
```

## Ntfy

Self-hosted [ntfy](https://ntfy.sh/) push-notification server, the
implementation-named server half of the notification pair, related to
[Notify](#notify) the way [Headscale](#headscale) relates to
[Tailscale](#tailscale).

### Options

```nix
{{#include ../../../modules/services/ntfy.nix:ntfy-options}}
```

## Notify

Host notification dispatch: the `othrys-notify` CLI and a
`notify-failure@.service` template that modules hook via `onFailure`, so
failing backups, SMART warnings, and UPS events reach a phone instead of
dying in the journal. Points at the local [Ntfy](#ntfy) server automatically
when both are enabled.

### Options

```nix
{{#include ../../../modules/services/notify.nix:notify-options}}
```

## WireGuard

Raw WireGuard interfaces for site-to-site links and exit nodes, the
coordination-server-free complement to [Tailscale](#tailscale). Private keys
are secrets-provider paths, and per-interface `openFirewall` opens the listen
port.

### Options

```nix
{{#include ../../../modules/services/wireguard.nix:wireguard-options}}
```

## DDNS

Dynamic DNS via inadyn, keeping hostnames pointing at a dynamic residential
IP, pairing with [Traefik](#traefik)'s DNS-01 ACME. Credentials arrive as an
inadyn include snippet (`password = <token>`) from a secrets provider.

### Options

```nix
{{#include ../../../modules/services/ddns.nix:ddns-options}}
```
