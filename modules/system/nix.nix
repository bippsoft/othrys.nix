# modules/system/nix.nix
# Nix daemon settings, substituters and garbage collection
{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.system.nix;
  # Shell snippet that loads the Cachix push token into the current process
  # only (used by the cachix-push wrapper), never exported to interactive shells.
  cachixTokenLoad = lib.optionalString (cfg.cachix.authTokenFile != null) ''
    if [ -r "${cfg.cachix.authTokenFile}" ]; then
      CACHIX_AUTH_TOKEN="$(cat "${cfg.cachix.authTokenFile}")"
      export CACHIX_AUTH_TOKEN
    fi
  '';
in {
  options.othrys.system.nix = {
    enable = lib.mkEnableOption "Nix package manager configuration";

    allowUnfree = lib.mkOption {
      type = lib.types.bool;
      # Defaults to false because this is licensing policy and a module library
      # has no standing to decide it for a consumer. Hosts that want unfree
      # packages say so, which also makes the choice visible in their own
      # configuration rather than inherited from an import.
      default = false;
      description = ''
        Allow unfree packages, by writing nixpkgs.config.allowUnfree. A policy
        decision, not a capability, so it defaults to false and hosts opt in.
        Hosts that instantiate nixpkgs themselves must set the policy on that
        instance instead, since nixpkgs.config is ignored when nixpkgs.pkgs is
        defined.
      '';
    };

    trustedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["root" "@wheel"];
      description = ''
        nix.settings.trusted-users. Trusted users can set arbitrary
        substituters and import unsigned store paths, effectively root over
        the store. Hardened multi-admin hosts should restrict this to
        ["root"].
      '';
    };

    stateVersion = lib.mkOption {
      type = lib.types.str;
      # Required: no default, mirroring othrys.system.user.name. stateVersion is
      # host identity rather than a library concern. A default would stamp every
      # consumer who forgets the option with whichever release this file happened
      # to name, and silently disagree with a host that sets system.stateVersion
      # itself. An unset value fails with the module system's "used but not
      # defined" error.
      example = "26.05";
      description = ''
        NixOS and home-manager state version, recording the release a host was
        first installed at. It governs the defaults of stateful services and is
        not a version to keep current, so set it once at install and leave it.
        This option is mandatory.
      '';
    };

    gc = {
      automatic = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable automatic garbage collection.";
      };

      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "When to run garbage collection.";
      };

      olderThan = lib.mkOption {
        type = lib.types.str;
        default = "7d";
        description = "Delete generations older than this.";
      };
    };

    nh = {
      enable =
        lib.mkEnableOption "nh (Nix CLI helper: nicer rebuild output + retention-aware GC)"
        // {default = true;};

      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/alice/nixos";
        description = "Absolute path nh uses as its default flake (NH_FLAKE), e.g. for `nh os switch`. Null leaves NH_FLAKE unset.";
      };

      clean = {
        enable =
          lib.mkEnableOption "periodic `nh clean all` (retention-aware; supersedes the timer-based nix.gc)"
          // {default = true;};

        extraArgs = lib.mkOption {
          type = lib.types.str;
          default = "--keep 5 --keep-since 7d";
          description = "Retention arguments passed to `nh clean all`.";
        };
      };
    };

    extraSubstituters = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional binary cache substituters.";
    };

    extraTrustedPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Additional trusted public keys for the substituters.";
    };

    cachix = {
      enable = lib.mkEnableOption "Cachix binary cache";

      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "my-cache";
        description = "Cachix cache name.";
      };

      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "my-cache.cachix.org-1:XXXXXX...";
        description = "Cachix cache public key for verification.";
      };

      authTokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "config.sops.secrets.\"system/cachix/auth-token\".path";
        description = "Path to file containing Cachix auth token for pushing.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # nixpkgs.config is ignored outright when a consumer supplies its own
    # nixpkgs instance through nixpkgs.pkgs (the NixOS test framework and
    # nixops both do). Writing the policy there would then be a silent no-op,
    # so fail loudly and make the consumer set it on the instance they own.
    assertions = [
      {
        assertion =
          !options.nixpkgs.pkgs.isDefined
          || (pkgs.config.allowUnfree or false) == cfg.allowUnfree;
        message = ''
          othrys.system.nix.allowUnfree is ${lib.boolToString cfg.allowUnfree} but
          nixpkgs.pkgs is defined externally, where nixpkgs.config is ignored, and
          that instance has allowUnfree = ${lib.boolToString (pkgs.config.allowUnfree or false)}.
          Set allowUnfree on the nixpkgs instance you pass in, or drop nixpkgs.pkgs
          and let this module configure nixpkgs.
        '';
      }
    ];

    # No mkDefault here, since nixpkgs.config is untyped attrs and override objects
    # would leak through to pkgs.config verbatim. The othrys option IS the
    # override mechanism.
    nixpkgs.config.allowUnfree = cfg.allowUnfree;

    # Home-manager must see the same nixpkgs policy as the system (unfree,
    # overlays). With its own instantiation, an unfree HM package fails even
    # though allowUnfree is on. mkDefault so consumers keep the last word.
    home-manager.useGlobalPkgs = lib.mkDefault true;
    home-manager.useUserPackages = lib.mkDefault true;

    nix.settings = {
      # Curated defaults, mkDefault so a host can replace them without
      # lib.mkForce (e.g. disable store optimisation on slow storage).
      experimental-features = lib.mkDefault ["nix-command" "flakes"];
      auto-optimise-store = lib.mkDefault true;

      trusted-users = cfg.trustedUsers;

      # Compositor caches are only useful on hosts building that compositor;
      # servers shouldn't query (or trust) a desktop cache on every miss.
      # NO mkDefault here, since upstream modules (hyprland, nix itself) contribute
      # to these list options at normal priority, and a mkDefault definition
      # would be discarded wholesale, silently dropping nix-community and
      # every curated entry. Hosts behind an internal mirror use lib.mkForce.
      substituters =
        [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ]
        ++ lib.optionals config.othrys.desktop.compositors.hyprland.enable [
          "https://hyprland.cachix.org"
        ]
        ++ lib.optionals config.othrys.desktop.compositors.niri.enable [
          "https://niri.cachix.org"
        ]
        ++ lib.optionals (cfg.cachix.enable && cfg.cachix.name != "") [
          "https://${cfg.cachix.name}.cachix.org"
        ]
        ++ cfg.extraSubstituters;

      trusted-public-keys =
        [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ]
        ++ lib.optionals config.othrys.desktop.compositors.hyprland.enable [
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        ]
        ++ lib.optionals config.othrys.desktop.compositors.niri.enable [
          "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
        ]
        ++ lib.optionals (cfg.cachix.enable && cfg.cachix.publicKey != "") [
          cfg.cachix.publicKey
        ]
        ++ cfg.extraTrustedPublicKeys;
    };

    programs.nh = lib.mkIf cfg.nh.enable {
      enable = true;
      inherit (cfg.nh) flake;
      clean = lib.mkIf cfg.nh.clean.enable {
        enable = true;
        inherit (cfg.nh.clean) extraArgs;
      };
    };

    # nh clean supersedes the timer-based nix.gc, and enabling both trips nh's own
    # assertion, so only wire nix.gc when nh isn't handling retention.
    nix.gc = lib.mkIf (!(cfg.nh.enable && cfg.nh.clean.enable)) {
      inherit (cfg.gc) automatic dates;
      options = "--delete-older-than ${cfg.gc.olderThan}";
    };

    system.stateVersion = cfg.stateVersion;

    # Only touch home-manager when othrys actually manages the user's
    # environment (users.homeManaged = account created AND homeManager on).
    # The guard wraps the whole `home-manager.users` write rather than just the leaf.
    # even a mkIf-false leaf would still materialize `home-manager.users.<name>`,
    # forcing home-manager to reference the user's home and trip NixOS's user
    # assertions on headless/root-only hosts that enable nix settings but no
    # primary user.
    home-manager.users = lib.mkIf config.othrys.system.users.homeManaged {
      ${username}.home.stateVersion = cfg.stateVersion;
    };

    # cachix-push <path>... loads the auth token only into the push process,
    # not every interactive shell, so it never leaks via /proc or subprocesses.
    environment.systemPackages = lib.mkIf cfg.cachix.enable [
      pkgs.cachix
      (pkgs.writeShellScriptBin "cachix-push" ''
        set -euo pipefail
        ${cachixTokenLoad}
        exec ${pkgs.cachix}/bin/cachix push ${cfg.cachix.name} "$@"
      '')
    ];
  };
}
