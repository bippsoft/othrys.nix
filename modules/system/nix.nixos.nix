# modules/system/nix.nixos.nix
# The NixOS implementation of othrys.system.nix
{
  config,
  options,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.othrys.system.nix;
  # The consumer's nixpkgs, which is what every host is built from, so the
  # registry and NIX_PATH point at the same revision as the system. It is
  # read from the consumer's `inputs` and never from this library's lock.
  # The registry entry is built from the flake, which carries the revision,
  # the hash and the date that a bare source path does not.
  #
  # A host that passes no `inputs` gets null here and is left with what NixOS
  # does on its own. `nixpkgs.lib.nixosSystem` records the source it was
  # called from, and NixOS pins the registry and NIX_PATH to that path.
  pinnedNixpkgs = inputs.nixpkgs or null;
  # Whether an externally supplied nixpkgs instance admits unfree packages by
  # an allowlist instead of the blanket switch.
  externalAllowlist =
    lib.isFunction (pkgs.config.allowUnfreePredicate or null)
    || (pkgs.config.allowUnfreePackages or []) != [];
  # Shell snippet that loads the Cachix push token into the current process
  # only (used by the cachix-push wrapper), never exported to interactive shells.
  cachixTokenLoad = lib.optionalString (cfg.cachix.authTokenFile != null) ''
    if [ -r "${cfg.cachix.authTokenFile}" ]; then
      CACHIX_AUTH_TOKEN="$(cat "${cfg.cachix.authTokenFile}")"
      export CACHIX_AUTH_TOKEN
    fi
  '';
in {
  imports = [./nix.nix];

  config = lib.mkIf cfg.enable {
    # nixpkgs.config is ignored outright when a consumer supplies its own
    # nixpkgs instance through nixpkgs.pkgs (the NixOS test framework and
    # nixops both do). Writing the policy there would then be a silent no-op,
    # so fail loudly and make the consumer set it on the instance they own.
    #
    # An instance that admits unfree packages through allowUnfreePredicate or
    # allowUnfreePackages reports allowUnfree = false while unfree evaluation
    # works, so either one satisfies allowUnfree = true here.
    assertions = [
      {
        assertion =
          !options.nixpkgs.pkgs.isDefined
          || (pkgs.config.allowUnfree or false) == cfg.allowUnfree
          || (cfg.allowUnfree && externalAllowlist);
        message = ''
          othrys.system.nix.allowUnfree is ${lib.boolToString cfg.allowUnfree} but
          nixpkgs.pkgs is defined externally, where nixpkgs.config is ignored, and
          that instance has allowUnfree = ${lib.boolToString (pkgs.config.allowUnfree or false)}
          and no allowUnfreePredicate or allowUnfreePackages.
          Set one of them on the nixpkgs instance you pass in, or drop nixpkgs.pkgs
          and let this module configure nixpkgs.
        '';
      }
    ];

    # No mkDefault here, since nixpkgs.config is untyped attrs and override objects
    # would leak through to pkgs.config verbatim. The othrys option IS the
    # override mechanism.
    # Skipped for an external instance, where NixOS rejects any nixpkgs.config
    # definition and the assertion above checks the instance instead.
    nixpkgs.config = lib.mkIf (!options.nixpkgs.pkgs.isDefined) {
      inherit (cfg) allowUnfree;
    };

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
        ["https://cache.nixos.org"]
        ++ lib.optional cfg.communityCache "https://nix-community.cachix.org"
        ++ lib.optionals config.othrys.desktop.compositors.hyprland.enable [
          "https://hyprland.cachix.org"
        ]
        ++ lib.optionals config.othrys.desktop.compositors.niri.enable [
          "https://niri.cachix.org"
        ]
        ++ lib.optional config.othrys.internal.llmAgentsCache "https://cache.numtide.com"
        ++ lib.optional cfg.cachix.enable "https://${cfg.cachix.name}.cachix.org"
        ++ cfg.extraSubstituters;

      trusted-public-keys =
        ["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="]
        ++ lib.optional cfg.communityCache "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ++ lib.optionals config.othrys.desktop.compositors.hyprland.enable [
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        ]
        ++ lib.optionals config.othrys.desktop.compositors.niri.enable [
          "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
        ]
        ++ lib.optional config.othrys.internal.llmAgentsCache "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        ++ lib.optional cfg.cachix.enable cfg.cachix.publicKey
        ++ cfg.extraTrustedPublicKeys;
    };

    # The registry and NIX_PATH point at the nixpkgs the host is built from,
    # so `nix run nixpkgs#foo` and `<nixpkgs>` resolve to that revision
    # instead of whatever the global registry fetches.
    nix.registry.nixpkgs.flake = lib.mkIf (pinnedNixpkgs != null) (lib.mkDefault pinnedNixpkgs);
    nix.nixPath = lib.mkIf (pinnedNixpkgs != null) ["nixpkgs=flake:nixpkgs"];

    # Channels are a second, unpinned source of nixpkgs, and nothing on a
    # flake host reads them once NIX_PATH names the registry. The global
    # registry is fetched from the network for every name the host does not
    # declare, so it is off unless a host asks for it.
    nix.channel.enable = lib.mkIf (pinnedNixpkgs != null) (lib.mkDefault false);
    nix.settings.flake-registry = lib.mkIf (!cfg.globalRegistry) (lib.mkDefault "");

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

    # cachix-push <path>... loads the auth token only into the push process,
    # not every interactive shell, so it never leaks via /proc or subprocesses.
    environment.systemPackages = lib.mkIf cfg.cachix.enable [
      pkgs.cachix
      (pkgs.writeShellScriptBin "cachix-push" ''
        set -euo pipefail
        ${cachixTokenLoad}
        exec ${pkgs.cachix}/bin/cachix push ${lib.escapeShellArg cfg.cachix.name} "$@"
      '')
    ];
  };
}
