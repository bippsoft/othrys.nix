# modules/system/nix.nix
# Nix daemon settings, substituters and garbage collection
{
  config,
  lib,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.system.nix;
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
      default = ["root"];
      description = ''
        nix.settings.trusted-users. A trusted user can set any substituter
        and import unsigned store paths, which is root over the store and so
        over the host, with no password and no YubiKey in the way. Root alone
        by default. A host that wants its administrators trusted adds
        "@wheel", and `nixos-rebuild switch` through sudo needs nothing, since
        it runs as root.
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

    globalRegistry = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Let Nix fetch the global flake registry, which resolves names such
        as `home-manager` or `flake-utils` to whatever the registry's
        maintainers point them at that day. Off, only the entries the host
        declares resolve, among them `nixpkgs`, pinned to the host's own
        input. A full reference such as `github:owner/repo` is unaffected.
      '';
    };

    communityCache = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Trust nix-community.cachix.org as a substituter. A trusted cache can
        serve any store path, so it is a trust root, and this one is added
        only when a host asks. The hyprland and niri caches are added with
        their compositors, since those flakes build nothing from
        cache.nixos.org, and cache.numtide.com with the AI modules whose
        package comes from the llm-agents input.
      '';
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
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression "config.sops.secrets.\"system/cachix/auth-token\".path";
        description = "Path to file containing Cachix auth token for pushing.";
      };
    };
  };

  # Set by each module whose package defaults to the llm-agents input. That
  # flake builds against its own nixpkgs, so cache.numtide.com is the only
  # place its packages come prebuilt from, and the cache is trusted on a host
  # only when one of those modules is on.
  options.othrys.internal.llmAgentsCache = lib.mkOption {
    type = lib.types.bool;
    default = false;
    internal = true;
    description = "Trust cache.numtide.com, for the packages of the llm-agents input.";
  };

  # What follows reads othrys options alone and holds on every platform, so
  # it sits beside the options rather than in each platform file.
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.cachix.enable || (cfg.cachix.name != "" && cfg.cachix.publicKey != "");
        message = "othrys.system.nix.cachix: set name and publicKey when the cache is enabled. An empty name pushed to nowhere, and an empty key left the substituter untrusted and silently ignored.";
      }
    ];

    # Per-user state goes through the registry rather than home-manager.users
    # directly, so nixosModules.home applies the homeManaged guard once, at
    # the attrset level. See modules/system/users.nix for why the guard cannot
    # sit on a leaf. Home Manager is also told to use the system's package
    # set by that export (modules/system/home.nix), which reads this module's
    # enable flag. The entry is withheld on a host with no managed user,
    # since a Home Manager state version means nothing there and the registry
    # warns about every entry it has to skip.
    othrys.internal.homeConfig."system.nix" = lib.mkIf config.othrys.system.users.homeManaged {
      home.stateVersion = cfg.stateVersion;
    };
  };
}
