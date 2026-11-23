# IRC with soju and senpai

A [soju](../modules/services.md#soju) bouncer on a server, behind Traefik, with
[senpai](../modules/apps.md#senpai) as the client on the same server and on a
laptop. soju stays connected to the networks and keeps their history, and each
senpai connects to soju and never to a network directly.

## Prerequisites

- A server built from this flake, with `irc.example.com` resolving to it
- A DNS provider whose API token Traefik can use for DNS-01 ACME
- `nixosModules.home` on the server and `nixosModules.home` or
  `darwinModules.home` on the laptop, since senpai is configured through Home
  Manager

## Steps

### 1. Turn on Traefik with ACME

```nix
othrys.services.traefik = {
  enable = true;
  acme = {
    enable = true;
    email = "alice@example.com";
    dnsProvider = "cloudflare";
  };
  environmentFiles = [config.sops.secrets."traefik/env".path];
};
```

Traefik terminates TLS for soju with the certificate this resolver issues, and
the soju module refuses `traefik.enable` while ACME is off.

### 2. Turn on soju

```nix
othrys.services.soju = {
  enable = true;
  traefik = {
    enable = true;
    domain = "irc.example.com";
  };
};
```

Traefik now listens on port 6697 and forwards to soju on `[::1]`. A client that
sends no TLS server name is not routed.

### 3. Create the First Account

```bash
sudo sojuctl user create -username alice -password 'change-me' -admin true
```

The module declares no accounts. The password is visible in the process list
while this command runs, and it is written to the shell history.

### 4. Configure senpai on the Server

```nix
othrys.apps.senpai = {
  enable = true;
  nickname = "alice";
  passwordFile = config.sops.secrets."senpai/password".path;
};
```

`address` defaults to soju's loopback listener, since soju is on the same host.
senpai logs in with `nickname` as the account name.

### 5. Configure senpai on the Laptop

```nix
othrys.apps.senpai = {
  enable = true;
  address = "irc.example.com";
  nickname = "alice";
  passwordFile = "/run/secrets/senpai-password";
  # Only when the nickname differs from the soju account name.
  # settings.username = "alice";
};
```

A bare host name connects with TLS on port 6697, which is Traefik's entrypoint
for soju.

### 6. Add an Upstream Network

From either senpai, ask soju's BouncerServ for the network.

```text
/msg BouncerServ network create -addr irc.libera.chat -name libera
```

soju connects to the network and keeps the connection open while no client is
attached. `/msg BouncerServ help` lists the other commands.
