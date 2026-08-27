# NixOS System Context

This is a NixOS system. You must understand these constraints:

## What You Cannot Do

- **No global package installs**: Never use `apt`, `yum`, `brew`, `pip install`, `npm install -g`, `cargo install`, `go install` for system-wide tools
- **No FHS paths**: Binaries are NOT in `/usr/bin/`, libraries NOT in `/usr/lib/` - they're in `/nix/store/`
- **No modifying /nix/store**: It's read-only and immutable
- **No persistent writes outside $HOME**: Root filesystem wipes on reboot (impermanence)

## What You Should Do

- **Temporary tools**: `nix run nixpkgs#<package>` or `nix shell nixpkgs#<package>`
- **Project dependencies**: Add to project's `flake.nix` devShell, then `nix develop`
- **Find packages**: Use NixOS MCP tools or `nix search nixpkgs <query>`
- **Task automation**: Create/update a `justfile` for project commands
- **Store data**: Only in `$HOME` (~/.config, ~/.local, project directories)

## Quick Reference

```bash
nix run nixpkgs#<pkg>      # Run package once without installing
nix shell nixpkgs#<pkg>    # Shell with package temporarily available
nix develop                # Enter project's dev shell (requires flake.nix)
nix search nixpkgs <query> # Search for packages
```

Project-specific instructions are in CLAUDE.md files.
