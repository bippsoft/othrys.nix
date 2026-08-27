# flake/dev-shells.nix
# Development shell environments
{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    config,
    ...
  }: let
    # Pre-commit hooks from git-hooks.nix (treefmt formats, statix and deadnix lint)
    pre-commit-check = inputs.git-hooks.lib.${system}.run {
      src = inputs.self;
      hooks = {
        treefmt = {
          enable = true;
          package = config.treefmt.build.wrapper;
        };
        statix.enable = true;
        deadnix.enable = true;
        commitizen.enable = true;
      };
    };
  in {
    # ANCHOR: dev-shells
    devShells = {
      default = pkgs.mkShell {
        name = "nixos-dev";
        packages = with pkgs; [
          # Nix tooling
          nixd
          alejandra
          statix
          deadnix

          # Git
          git
          gh
          commitizen # `just release` bumps and writes CHANGELOG.md with this

          # Nix utilities
          nix-tree
          nix-diff
          nvd
          nix-output-monitor

          # Data formats
          jq
          yq-go

          # Documentation
          mdbook
        ];

        # Install pre-commit hooks on shell entry
        shellHook = ''
          ${pre-commit-check.shellHook}
        '';
      };

      javascript = pkgs.mkShell {
        name = "javascript-dev";
        packages = with pkgs; [
          nodejs_22
          pnpm
          yarn
          bun
          typescript
          typescript-language-server
          eslint
          prettier
          vite
        ];
      };

      python = pkgs.mkShell {
        name = "python-dev";
        packages = with pkgs; [
          python312
          python312Packages.pip
          python312Packages.virtualenv
          poetry
          python312Packages.black
          python312Packages.pylint
          python312Packages.pytest
          python312Packages.python-lsp-server
        ];
      };

      golang = pkgs.mkShell {
        name = "golang-dev";
        packages = with pkgs; [
          go
          gopls
          gotools
          go-tools
          delve
          golangci-lint
        ];
        shellHook = ''
          export GOPATH="$HOME/go"
          export PATH="$GOPATH/bin:$PATH"
        '';
      };

      java = pkgs.mkShell {
        name = "java-dev";
        packages = with pkgs; [
          jdk21
          maven
          gradle
        ];
      };

      iac = pkgs.mkShell {
        name = "iac-dev";
        packages = with pkgs; [
          opentofu
          terraform-ls
          tflint
          ansible
          ansible-lint
          awscli2
          kubectl
          kubernetes-helm
          k9s
          sops
          age
        ];
      };

      rust = pkgs.mkShell {
        name = "rust-dev";
        packages = with pkgs; [
          rustc
          cargo
          rust-analyzer
          rustfmt
          clippy
          cargo-watch
          cargo-edit
          cargo-audit
        ];
        RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
      };
    };
    # ANCHOR_END: dev-shells
  };
}
