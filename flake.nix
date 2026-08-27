{
  description = "othrys.nix - NixOS configuration with flakes";

  # All external dependencies for this flake
  # ANCHOR: inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Flake framework for modular configuration
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      # Deliberately does not follow nixpkgs, for cache hits rather than for
      # any build failure. Upstream builds against its own pin, so
      # hyprland.cachix.org serves the exact derivations this flake asks for.
      # Adding `follows` while still reading inputs.hyprland.packages changes
      # those hashes and puts every consumer on a source build, which is the
      # one combination to avoid.
      #
      # nixpkgs carries hyprland too, so defaulting to pkgs.hyprland with
      # mkDefault (what the niri module does) is viable and would drop the
      # second nixpkgs this input costs. Left alone because no check here can
      # prove a packaging swap leaves a live session behaving the same.
      url = "github:hyprwm/Hyprland";
    };

    ashell = {
      url = "github:MalpenZibo/ashell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Niri compositor, packages plus the typed programs.niri.settings module
    # (build-time-validated KDL config). Self-contained, since the compositor
    # module imports its NixOS module directly, and its auto-cache is disabled in
    # favor of the curated substituter list in othrys.system.nix.
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      # nixpkgs-stable is deliberately left unfollowed. niri-flake builds its
      # stable package set against it, and pointing it at unstable defeats
      # what the separate pin exists for. It is the second-largest node in the
      # lock after hyprland's nixpkgs and it stays on purpose.
    };

    # Noctalia Wayland desktop shell (bar/launcher/notifications/lock/...).
    # Self-contained, since the module imports its home-manager module directly.
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-index database, a prebuilt index for comma and nix-locate
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Impermanence, opt-in state persistence
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nixvim - Neovim configuration with Nix modules
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    # Stylix - System-wide theming using base16
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    # nixos-hardware - Hardware-specific configurations and optimizations
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Git hooks for pre-commit validation
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Multi-language formatting (drives `nix fmt` + the treefmt pre-commit hook)
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management with age encryption
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  # ANCHOR_END: inputs

  # All outputs defined using flake-parts framework
  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      # Define which systems this flake supports
      # flake-parts will automatically evaluate perSystem for each of these
      systems = [
        "x86_64-linux"
        # Add more systems if needed:
        # "aarch64-linux"   # ARM64 Linux (Raspberry Pi, etc.)
        # "x86_64-darwin"   # Intel macOS
        # "aarch64-darwin"  # Apple Silicon macOS
      ];

      # Import modular flake-parts modules
      # Each module defines specific outputs (nixosConfigurations, devShells, etc.)
      # ANCHOR: imports
      imports = [
        inputs.treefmt-nix.flakeModule

        ./flake/modules.nix # Exported nixosModules
        ./flake/packages.nix # Packaged scripts and tools
        ./flake/dev-shells.nix # Development environments
        ./flake/treefmt.nix # Multi-language formatter (nix fmt)
        ./flake/docs-options.nix # Generated othrys.* options reference
        ./flake/checks # CI/CD checks
      ];
      # ANCHOR_END: imports

      # Additional per-system outputs can be defined here
      # This is evaluated once for each system in the systems list
      #
      # Available arguments:
      # - config: Current perSystem configuration
      # - self': System-specific access to this flake's outputs
      # - inputs': System-specific access to input flake outputs
      # - pkgs: Nixpkgs for the current system
      # - system: Current system string (e.g., "x86_64-linux")
      #
      # perSystem = { config, self', inputs', pkgs, system, ... }: {
      #   # Additional packages, apps, or other per-system outputs
      # };

      # Additional top-level flake attributes can be defined here
      # These are not system-specific
      #
      # flake = {
      #   # Examples:
      #   # nixosModules.myModule = import ./modules/my-module.nix;
      #   # overlays.default = import ./overlays;
      # };
    };
}
