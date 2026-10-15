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

Two options place material in the store on purpose, and each says so in its
description.

| Option | What lands in the store | Why it is accepted |
|--------|-------------------------|--------------------|
| `othrys.system.users.initialHashedPassword` | A password hash | It bootstraps the first boot before secrets decrypt. Treat the hash as public and move the host to `passwordFile` |
| `othrys.system.secrets.ageIdentityStubs` | An `age-plugin-yubikey` stub | The stub names a hardware token and holds no key. An assertion rejects a raw `AGE-SECRET-KEY` |

Where a service only accepts a secret inside its own configuration file, the
module renders that file under `/run` at start from the runtime path. The ntfy
bridge token in `alerting.nix` is handled this way.

Where a program only reads a credential from its environment, the module
installs a wrapper that reads the runtime path into the variable for that one
process and then becomes the program. `cachix-push` loads the cache token this
way, and `gh` loads `othrys.apps.gh.tokenFile` the same way on a headless
host. The variable is never set in a shell, so nothing else started from that
shell inherits it.

No module keeps a credential of its own. `modules/system/secrets.nix` is the
only file that writes into the `sops` namespace, where it sets the decryption
keys, and every secret is declared by the consuming flake. On a desktop the
`gh` login lives in the Secret Service keyring, which
`othrys.desktop.keyring` provides, and Claude Code keeps its own login under
`~/.claude`.

## Trust roots

A host built from these modules trusts the following, and nothing in this
repository can reduce that set.

- **The consuming flake's repository.** `othrys.system.autoUpgrade` runs
  `nixos-rebuild switch` against whatever the configured flake ref resolves to,
  so by default write access to that repository is root on every host that
  follows it. With `autoUpgrade.verify` on, the host fetches the repository
  itself, requires a good signature from a configured key on the commit or tag,
  refuses anything that does not descend from the last verified commit, and
  rebuilds from that checkout. The signing keys then take the repository's place
  as the trust root. Only the tip is verified, and the signature covers
  `flake.lock`, which pins every input by hash.
- **The flake lock.** Every input is pinned by content hash in the consuming
  flake's `flake.lock`, this repository included. A changed input cannot reach a
  host without a changed lock.
- **Binary caches.** A substituter with a trusted public key can serve any store
  path. Every host trusts `cache.nixos.org`. `othrys.system.nix.communityCache`
  adds `nix-community.cachix.org` when a host asks, the hyprland and niri
  caches come with their compositor modules, and `othrys.system.nix.cachix.*`
  lets a consumer add their own cache. The cache this repository's CI pushes
  to is a build cache for CI and is not meant for hosts.
- **Trusted Nix users.** `nix.settings.trusted-users` is root alone by
  default. A trusted user can point the daemon at any substituter and import
  unsigned paths, which is root over the host with no password and no second
  factor, so `@wheel` is added only by a host that wants it. The primary user
  is in `wheel` by default, which is sudo and nothing more.
- **Release tags.** Tags from `v0.4.0` onward are signed. Earlier tags are not,
  and a consumer pinning one of them relies on GitHub alone.
- **CI credentials.** `CACHIX_AUTH_TOKEN` can write to the CI cache.
  `MAINTENANCE_CLIENT_ID` and `MAINTENANCE_SECRET` are the client ID and
  private key of a GitHub App installed on this repository alone, and the
  token minted from them can push branches and open pull requests here for
  an hour. Neither can write to `main`, which is protected and needs passing
  checks.

The registry resolves `nixpkgs` to the host's own input. Channels are off on
a host built from a flake, and the global flake registry is not fetched unless
`othrys.system.nix.globalRegistry` is set, so an indirect name such as
`home-manager` resolves only when the host declares it.

## Authentication

The YubiKey module makes the key a second factor by default. pam_u2f is
inserted as `required` into the services listed in `u2fServices`, so the
password and the touch must both succeed. The PAM control applies to the whole
service, which means every account that authenticates through one of those
services needs an enrolled credential. An account without one is locked out of
them, and that includes a service account an administrator logs into rarely.
Setting `u2fRequirePassword = false` switches the control to `sufficient`, where
a touch replaces the password and an account with no credential falls through
to its password. See [Security](../modules/security.md).

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
