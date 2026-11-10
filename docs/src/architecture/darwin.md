# Darwin

othrys.nix builds nix-darwin hosts as well as NixOS ones. The darwin exports
take the same `othrys.*` option names, so a module that runs on both
platforms is configured the same way on each, and a NixOS-only module is not
in the darwin tree at all. `aarch64-darwin` is the darwin platform the checks
build. The options reference marks each option with the platforms that
declare it (see [Module Options](../reference/options.md)).

## The Exports

A nix-darwin host imports `othrys.darwinModules.default`, the same set as
`othrys.modules.darwin.default`. It holds the primary user, the account,
Nix, git, the locale, the shell modules, the theme, SSH, Tailscale, Mosh,
the YubiKey and the apps that build for darwin, under the option names a NixOS
host uses. The apps are `gh`, `yazi`, `comma`, nixvim, Claude Code, Codex,
Ollama and the MCP servers, the language registry, Ghostty, kitty, mpv,
VSCodium, IntelliJ IDEA and Signal.
Picard is left out, since its `pyqt6` fails to build on darwin in the
pinned nixpkgs. Most are the darwin implementations of split
modules (see
[Module System](./module-system.md#shared-options-and-platform-files)), and
the rest, such as bash, starship and the theme, write only options nix-darwin
declares as well. The export imports no
upstream module, so a host built from it alone imports nothing else.

```nix
inputs.nix-darwin.lib.darwinSystem {
  specialArgs = {inherit inputs;};
  modules = [
    inputs.othrys.darwinModules.default
    inputs.othrys.darwinModules.home
    inputs.home-manager.darwinModules.home-manager
    {
      nixpkgs.hostPlatform = "aarch64-darwin";
      system.stateVersion = 6;
      othrys.system = {
        user.name = "alice";
        users.enable = true;
        nix = {
          enable = true;
          stateVersion = "26.05";
        };
      };
    }
  ];
}
```


## The Account, Nix and the Locale

macOS creates the administrator account at setup, and the module leaves it
with macOS. `othrys.system.users.enable` sets the account's home to
`/Users/<name>` and makes it `system.primaryUser`, which nix-darwin needs for
`system.defaults` and launchd user agents. nix-darwin applies a login shell
only to an account it owns, and owning one takes a uid, so the shell from
`othrys.system.users.defaultShell` applies only once the host sets
`othrys.system.users.uid`. nix-darwin then lists the account in
`users.knownUsers` and may create it.

`othrys.system.nix` leaves `nix.enable` to nix-darwin and defaults
`nix.package` to Lix. `system.stateVersion` is an integer on nix-darwin,
which the host sets itself, while `othrys.system.nix.stateVersion` remains
the Home Manager state version. The store is optimised by the scheduled
`nix.optimise` job, since nix-darwin refuses `auto-optimise-store` on Nix
and Lix releases that corrupt the store with it on macOS.
`othrys.system.locale` sets `time.timeZone` and `LANG`, since nix-darwin
has no `i18n` and no console options. `othrys.desktop.graphical` defaults to
true on a Mac.


## Home Manager and the Apps

`darwinModules.home` is the same adapter as `nixosModules.home`, and it hands
the registry of user configuration to Home Manager's darwin module in the
same way. An account with Home Manager on and no adapter imported is refused,
and `othrys.system.users.homeManager.enable = false` keeps an account Home
Manager does not manage. Ghostty takes `ghostty-bin` on darwin, since nixpkgs
builds `ghostty` for Linux alone. The persistence registry is declared and
nothing reads it, since a Mac has no ephemeral root, and the assistants'
context leaves out the NixOS text there.


## Services

SSH writes the known hosts and the client configuration as on NixOS, and
`server.enable` turns on Remote Login with the hardened settings, on port 22
alone. Tailscale runs tailscaled and refuses the options that only
`tailscale up` and `tailscale set` apply, since nix-darwin runs neither.
Mosh puts `mosh` on the system path, where sshd finds `mosh-server` for an
account whose shell is zsh. The YubiKey module keeps the GnuPG agent with
`pinentry_mac` and refuses a U2F mapping. Ollama runs as the user's launchd
agent through Home Manager, with nixpkgs' one darwin build. See
[Services](../modules/services.md), [Security](../modules/security.md) and
[AI](../modules/ai.md) for each.


## Adapters

`darwinModules.stylix` and `darwinModules.secrets` are the darwin forms of
the NixOS adapters, and a host imports each with `darwinModules.stylix` of
the stylix flake or `darwinModules.sops` of the sops-nix flake. Stylix on
darwin themes the fonts, jankyborders and neovim, and the rest of what it
themes is in the user's Home Manager configuration, so a host with the
Stylix adapter imports `darwinModules.home` as well. It sets no cursor and
turns the user's GTK target off there. The secrets adapter takes no ssh host
key, since a Mac may have none, and generates an age key at
`sops.age.keyFile`. A host that names no age key, ssh key or GnuPG home is
refused.
`darwinModules.full` is `default` with `home`, `stylix` and `secrets` and the
three upstream darwin modules, taken from this flake's lock, so a host built
from it imports nothing else.

```nix
inputs.nix-darwin.lib.darwinSystem {
  specialArgs = {inherit inputs;};
  modules = [
    inputs.othrys.darwinModules.full
    {
      nixpkgs.hostPlatform = "aarch64-darwin";
      system.stateVersion = 6;
      othrys.system = {
        user.name = "alice";
        users.enable = true;
        nix = {
          enable = true;
          stateVersion = "26.05";
        };
        stylix.enable = true;
        secrets.enable = true;
      };
      sops.age = {
        keyFile = "/var/lib/sops-nix/key.txt";
        generateKey = true;
      };
    }
  ];
}
```


## The Template

`nix flake init -t github:bippsoft/othrys.nix#darwin` writes a consuming
flake for one Mac, `darwinConfigurations.mymac`, built from
`darwinModules.full`. Its inputs are othrys, with `nixpkgs` and `nix-darwin`
following the lock of othrys, and nothing else, since `full` brings Home
Manager, Stylix and sops-nix from that lock. `configuration.nix` names the
administrator account as the primary user, leaves Home Manager managing it
and turns on Nix, the locale, zsh and the SSH client. nix-darwin manages
the Nix installation and othrys sets Lix as its package. Any Nix or Lix
installation runs the first switch, which moves the daemon to Lix. The
first switch takes nix-darwin from the template's own lock:

```bash
sudo nix run --inputs-from . nix-darwin -- switch --flake .#mymac
```

Later switches run `sudo darwin-rebuild switch --flake .#mymac`.

`eval-darwin-template` instantiates the template with only those inputs. It
fails on any warning, on a Nix other than Lix and on an account Home Manager
does not manage, and on a Mac it builds the toplevel.

## What Is Tested

The `core-darwin` job builds the darwin checks on an Apple Silicon runner,
and the core job evaluates the same hosts on Linux with
import-from-derivation off. The hosts are a user named and nothing on, the
system modules with Home Manager, every darwin app on, `darwinModules.full`
with Stylix and the secrets plumbing, one host for each darwin service module
on by itself and the template. `eval-darwin` reads back what the modules
write there. `darwin-enable-matrix` in the darwin leg of the extended tier
turns every darwin enable option on by itself, and `eval-contract` holds the
darwin hosts to the consumer contract. No check activates a system on a Mac,
so a setting that macOS reads at activation or at run time is unchecked. See
[CI/CD](../development/ci.md).

## What Stays on NixOS

Disko, impermanence, the bootloader, the compositors and the rest of the
desktop, the hardware modules and every service module other than SSH,
Tailscale, Mosh and the YubiKey are NixOS only. nix-darwin declares none of the
options they write, and a Mac has no ephemeral root, no Linux boot chain and
no compositor for othrys to manage. The apps outside the list under
[The Exports](#the-exports) stay on NixOS too, among them Picard, whose
`pyqt6` fails to build on darwin, and Chromium, which nixpkgs builds for
Linux alone.
