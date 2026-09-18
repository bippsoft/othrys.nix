# Security Model

This page states what othrys.nix protects, what it trusts, and where protection
stops. The reasoning for single options lives beside those options. This page
collects the parts that span modules, so a consumer can read the whole position
in one place.

## What reaches the Nix store

The Nix store is world-readable, and a path stays in it for as long as any
generation refers to it. Anything a module interpolates into a derivation is
therefore public to every user and every process on the host.

Modules that need credentials take a runtime path and never the credential
itself. The `secretPath` type in `modules/lib/types.nix` rejects path literals
and store paths, since a literal such as `./token` is copied into the store the
moment it is interpolated. The consuming flake decides what writes the file at
that path, which is typically sops-nix decrypting to `/run/secrets` at
activation. See [Secrets Management](../system/secrets.md).

Three options place material in the store on purpose, and each says so in its
description.

| Option | What lands in the store | Why it is accepted |
|--------|-------------------------|--------------------|
| `othrys.system.users.initialHashedPassword` | A password hash | It bootstraps the first boot before secrets decrypt. Treat the hash as public and move the host to `passwordFile` |
| `othrys.system.secrets.ageIdentityStubs` | An `age-plugin-yubikey` stub | The stub names a hardware token and holds no key. An assertion rejects a raw `AGE-SECRET-KEY` |
| `othrys.services.containerization.k3s.token` | The cluster join token | It exists for throwaway clusters. `tokenFile` is the form to use |

Where a service only accepts a secret inside its own configuration file, the
module renders that file under `/run` at start from the runtime path. The ntfy
bridge token in `alerting.nix` is handled this way.

## Trust roots

A host built from these modules trusts the following, and nothing in this
repository can reduce that set.

- **The consuming flake's repository.** `othrys.system.autoUpgrade` runs
  `nixos-rebuild switch` against whatever the configured flake ref resolves to.
  No signature is checked, so write access to that repository is root on every
  host that follows it.
- **The flake lock.** Every input is pinned by content hash in the consuming
  flake's `flake.lock`, this repository included. A changed input cannot reach a
  host without a changed lock.
- **Binary caches.** A substituter with a trusted public key can serve any store
  path. `othrys.system.nix.cachix.*` lets a consumer add their own cache and
  adds none by default. The cache this repository's CI pushes to is a build
  cache for CI and is not meant for hosts.
- **Release tags.** Tags from `v0.4.0` onward are signed. Earlier tags are not,
  and a consumer pinning one of them relies on GitHub alone.
- **CI credentials.** `CACHIX_AUTH_TOKEN` can write to the CI cache, and
  `FLAKE_UPDATE_TOKEN` can push branches and open pull requests here. Neither
  can write to `main`, which is protected and needs passing checks.

## Authentication

The YubiKey module offers the key as a sufficient factor by default, so a touch
replaces the password. `u2fRequirePassword` makes both required. The PAM control
applies to the whole service, which means every account on the host then needs
an enrolled credential for `login` and `sudo`. An account without one is locked
out of both, and that includes a service account an administrator logs into
rarely. See [Security](../modules/security.md).

## Network inspection fails open

With the router handing forwarded traffic to Suricata over NFQUEUE, two
mechanisms decide what happens when inspection stops. The `bypass` flag on the
queue accepts packets while no process is bound to it, and
`othrys.services.suricata.nfqueue.failOpen` accepts them while the queue is
full. Both are deliberate, since an IPS fault on a router should not cut off the
network behind it. While Suricata is down the link stays up and forwarded
traffic is not inspected. See [Services](../modules/services.md).

## Boot chain

The disko layout encrypts the root with LUKS, with an optional FIDO2 unlock, and
that protects data at rest. It does not protect the boot chain. The kernel and
the initrd sit unencrypted on the EFI system partition, and someone with
physical access can replace them with a copy that records the passphrase at the
next unlock.

Secure Boot closes that gap by having the firmware verify what it loads.
`othrys.system.bootloader.secureBoot` supports it on Limine, which is the
default bootloader, and on `systemd-boot` through lanzaboote when the consuming
flake imports that module. GRUB has no Secure Boot path in NixOS and the option
is rejected there. The firmware enforces nothing until the keys are enrolled,
which is a manual step. See [Bootloader & Secure Boot](../system/bootloader.md)
and the [Secure Boot guide](../guides/secure-boot.md).

No measured boot option exists. The LUKS key is not bound to TPM PCR values, so
a changed boot chain does not by itself prevent an unlock.

## SSH host trust

`othrys.services.ssh.knownHosts` distributes host keys to every user, and the
published keys of four public forges are included by default. A host that is
not listed still prompts on the first connection, and whoever answers accepts
it on trust. Setting `StrictHostKeyChecking yes` through `settings` refuses
unlisted hosts and ends that. There is no host certificate authority option, so
each host key is listed one by one. See [Services](../modules/services.md).

## AI assistants

`othrys.apps.ai.claude-code` ships allow and deny lists for the tools the
assistant can run without asking. The lists limit accidents and are not a
sandbox. See [AI Assistants](../modules/ai.md).
