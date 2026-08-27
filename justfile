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

# Cut a release: commitizen derives the version from conventional commits since
# the last tag, writes CHANGELOG.md, commits it and tags vX.Y.Z. Pass a bump
# explicitly (major/minor/patch) to override what it infers.
release bump="":
    #!/usr/bin/env bash
    set -euo pipefail
    just ci
    if [[ -n "{{bump}}" ]]; then
        nix develop -c cz bump --increment "{{bump}}" --changelog
    else
        nix develop -c cz bump --changelog
    fi
    tag="$(git describe --tags --abbrev=0)"
    echo "Tagged $tag, publish with: git push origin main \"$tag\""
