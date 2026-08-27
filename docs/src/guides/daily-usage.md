# Daily Usage

Common workflows for maintaining a system built on these modules. Host commands run from your fleet repo, development commands from either repo.

## Rebuild Workflow

```bash
# 1. Build without applying (syntax + dependency check)
just build <hostname>

# 2. Show what will change
just diff <hostname>

# 3. Test changes (temporary, reverts on reboot)
just test <hostname>

# 4. Apply permanently
just switch <hostname>
```

## Update Dependencies

```bash
# Update all flake inputs
just update

# Update a specific input
just update nixpkgs
```

## Maintenance

```bash
# Garbage collect + optimize (delete generations older than 7 days)
just maintain

# Just garbage collect
just gc 7d

# Optimize nix store
just optimize

# Remove build artifacts
just clean
```

## Rollback

Since impermanence wipes root on boot, rollback works at the bootloader level. Previous generations are available in the boot menu.

## Development

```bash
# Enter the default dev shell
just dev

# Enter a specific dev shell
just dev rust
just dev python
just dev javascript
```
