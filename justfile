# othrys.nix - public NixOS module library

set shell := ["bash", "-uc"]
set positional-arguments

# Show available commands
default:
    @just --list

# Update flake inputs (all or specific input)
update input="":
    #!/usr/bin/env bash
    if [[ -z "{{input}}" ]]; then
        nix flake update
    else
        nix flake update "{{input}}"
    fi

# Validate flake (eval + checks)
check:
    nix flake check

# Format the repo (treefmt: nix, shell, toml, yaml, markdown)
fmt:
    nix fmt

# Enter development shell
dev shell="":
    #!/usr/bin/env bash
    if [[ -z "{{shell}}" ]]; then
        nix develop
    else
        nix develop ".#{{shell}}"
    fi

# Open nix repl
repl:
    nix repl

# Remove local build artifacts
clean:
    rm -f result result-*

# Build, serve, or clean MdBook documentation
docs action="build":
    #!/usr/bin/env bash
    set -euo pipefail
    gen_options() {
        install -m644 "$(nix build --no-link --print-out-paths .#options-doc)" docs/src/reference/options.md
    }
    case "{{action}}" in
        build) gen_options && mdbook build docs/ ;;
        serve) gen_options && mdbook serve docs/ --open ;;
        clean) mdbook clean docs/ && rm -f docs/src/reference/options.md ;;
        *) echo "Unknown action: {{action}}. Use build, serve, or clean." && exit 1 ;;
    esac

# Onboard a new YubiKey (interactive)
yubikey-onboard *args="":
    nix run ".#yubikey-onboard" -- {{args}}

# Run all CI checks (format, lint, flake check)
ci: lint
    @echo "Running flake check..."
    nix flake check
    @echo "All CI checks passed!"

# Run linters (format check, statix, deadnix)
#
# statix and deadnix come from the dev shell rather than `nix run nixpkgs#...`,
# which resolves through the flake registry instead of flake.lock and can run a
# different version locally than CI and the pre-commit hook do.
lint:
    @echo "Checking formatting..."
    nix fmt -- --ci
    @echo "Running statix..."
    nix develop -c statix check .
    @echo "Running deadnix..."
    nix develop -c deadnix --fail .

# Tag a release (vX.Y.Z) after the full check suite passes
release version:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{version}}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like v0.4.0"; exit 1; }
    just ci
    git tag -a "{{version}}" -m "othrys.nix {{version}}"
    echo "Tagged {{version}}, publish with: git push origin {{version}}"
