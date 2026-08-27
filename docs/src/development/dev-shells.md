# Dev Shells

Development environments defined in `flake/dev-shells.nix`.

## Available Shells

```nix
{{#include ../../../flake/dev-shells.nix:dev-shells}}
```

## Usage

```bash
# Enter the default shell (Nix tooling + pre-commit hooks)
just dev

# Enter a specific shell
just dev javascript
just dev python
just dev golang
just dev java
just dev iac
just dev rust
```

## Direnv Integration

The repository includes an `.envrc` that automatically activates the default dev shell when you enter the directory. This provides Nix tooling and pre-commit hooks without manual `nix develop`.

## Adding a New Shell

Add a new entry to the `devShells` attrset in `flake/dev-shells.nix`:

```nix
myshell = pkgs.mkShell {
  name = "myshell-dev";
  packages = with pkgs; [ ... ];
};
```
