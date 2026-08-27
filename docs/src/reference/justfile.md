# Justfile Commands

Each repository carries its own justfile. This one covers library development, while a consuming fleet's covers host management. Run `just` in either repo to see available commands.

## othrys.nix (this repository)

| Command | Description |
|---------|-------------|
| `just check` | Validate flake (eval + checks) |
| `just fmt` | Format the repo (treefmt) |
| `just lint` | Format check + statix + deadnix |
| `just ci` | lint + flake check |
| `just update [input]` | Update flake inputs |
| `just docs [build\|serve\|clean]` | MdBook documentation |
| `just dev [shell]` | Enter dev shell |
| `just repl` | Open Nix REPL |
| `just clean` | Remove build artifacts |
| `just yubikey-onboard [args]` | Onboard/rotate YubiKey(s) ([options](../guides/yubikey-onboard.md#options)) |

## Consuming fleet (recommended layout)

| Command | Description |
|---------|-------------|
| `just build [host]` | Build a host (defaults to current hostname) |
| `just test [host]` | Test configuration (reverts on reboot) |
| `just switch [host]` | Apply configuration permanently |
| `just boot [host]` | Set configuration for next boot |
| `just diff [host]` | Show diff between current and new configuration |
| `just update [input]` | Update flake inputs (incl. `secrets`, `othrys`) |
| `just check` | Validate flake (hosts must evaluate) |
| `just fmt` | Format (treefmt, re-exported from othrys.nix) |
| `just gc [age]` / `just maintain [age]` | Garbage collect / GC + optimize |
| `just disk <host>` / `just install <host>` | Fresh-install workflow |
| `just luks-enroll` | Enroll a YubiKey into the LUKS keyslot |
| `just ci` | lint + check + build every host |

## Upgrade Pattern

The `test`, `switch`, and `boot` commands accept an `upgrade` argument to update inputs first:

```bash
just switch <hostname> upgrade
```
