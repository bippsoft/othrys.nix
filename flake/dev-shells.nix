# flake/dev-shells.nix
# Development shell environments
{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    portableHooks,
    repositoryHooks,
    ...
  }: let
    # Both hook sets are named in ./checks/default.nix, which builds
    # pre-commit-check from the same two, so a commit in this repository meets
    # locally every hook it will meet in CI.
    # hookIds is read back by the eval-dev-shells check, which is how the two
    # shells are held to the hooks they claim to install.
    shellFor = hooks: let
      run = inputs.git-hooks.lib.${system}.run {
        src = inputs.self;
        inherit hooks;
      };
    in
      pkgs.mkShell {
        name = "nixos-dev";
        packages = tools;
        # Install pre-commit hooks on shell entry
        inherit (run) shellHook;
        passthru.hookIds = builtins.attrNames (pkgs.lib.filterAttrs (_: hook: hook.enable) run.config.hooks);
      };

    tools = with pkgs; [
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
  in {
    # ANCHOR: dev-shells
    devShells = {
      # For work on this repository. Installs every hook on shell entry.
      default = shellFor (portableHooks // repositoryHooks);

      # For a flake that re-exports the shell. Same tools, portable hooks only.
      # The repository hooks check this repository's own tree and reject any
      # other, so a consumer points its default here:
      #   devShells.default = inputs'.othrys.devShells.consumer;
      consumer = shellFor portableHooks;

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
