# modules/system/nix.darwin.nix
# The nix-darwin implementation of othrys.system.nix
{
  config,
  options,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.othrys.system.nix;
  # The consumer's nixpkgs, read from the consumer's `inputs` as in
  # nix.nixos.nix. A host that passes no `inputs` gets null here, and
  # nix-darwin then pins the registry and NIX_PATH itself from
  # nixpkgs.flake.source, which darwinSystem records from its own nixpkgs.
  # With a pin here nix-darwin's own pin is turned off, since the two name
  # different paths whenever nix-darwin's nixpkgs does not follow the host's
  # and the registry entry takes one.
  pinnedNixpkgs = inputs.nixpkgs or null;
  externalAllowlist =
    lib.isFunction (pkgs.config.allowUnfreePredicate or null)
    || (pkgs.config.allowUnfreePackages or []) != [];
  cachixTokenLoad = lib.optionalString (cfg.cachix.authTokenFile != null) ''
    if [ -r "${cfg.cachix.authTokenFile}" ]; then
      CACHIX_AUTH_TOKEN="$(cat "${cfg.cachix.authTokenFile}")"
      export CACHIX_AUTH_TOKEN
    fi
  '';
  # nix-darwin asserts nix.enable for every launchd job that runs Nix. A host
  # that leaves the installation to another installer turns nix.enable off
  # and keeps that installer's own collection and optimisation.
  daemonManaged = config.nix.enable;
  nhCleans = cfg.nh.enable && cfg.nh.clean.enable && daemonManaged;
in {
  imports = [./nix.nix];

  config = lib.mkIf cfg.enable {
    # nix-darwin ignores nixpkgs.config when nixpkgs.pkgs is set, as NixOS
    # does, so the policy is checked on the instance the host passes in.
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

    # nix.gc on nix-darwin is a launchd calendar interval, not a systemd
    # calendar expression, and gc.dates holds the latter. nix-darwin's
    # default interval is Sunday at 03:15, which is the "weekly" that
    # gc.dates defaults to, so only a changed value is lost.
    warnings = lib.optional (daemonManaged && !nhCleans && cfg.gc.automatic && cfg.gc.dates != "weekly") ''
      othrys.system.nix.gc.dates is "${cfg.gc.dates}", a systemd calendar
      expression that nix-darwin cannot read. Garbage collection runs at
      nix.gc.interval, which defaults to Sunday at 03:15. Set nix.gc.interval
      on this host to change it.
    '';

    nixpkgs.config = lib.mkIf (!options.nixpkgs.pkgs.isDefined) {
      inherit (cfg) allowUnfree;
    };

    # Darwin hosts run Lix. mkDefault, so a host can return to pkgs.nix.
    nix.package = lib.mkDefault pkgs.lix;

    # auto-optimise-store is left unset. nix-darwin asserts against it on
    # every Nix and Lix release older than the fix for a store corruption it
    # causes on macOS, and the scheduled optimiser below does the same work.
    nix.settings = {
      experimental-features = lib.mkDefault ["nix-command" "flakes"];

      trusted-users = cfg.trustedUsers;

      # The compositor caches of nix.nixos.nix are absent, since neither
      # compositor builds on macOS and their options are not declared here.
      substituters =
        ["https://cache.nixos.org"]
        ++ lib.optional cfg.communityCache "https://nix-community.cachix.org"
        ++ lib.optional config.othrys.internal.llmAgentsCache "https://cache.numtide.com"
        ++ lib.optional cfg.cachix.enable "https://${cfg.cachix.name}.cachix.org"
        ++ cfg.extraSubstituters;

      trusted-public-keys =
        ["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="]
        ++ lib.optional cfg.communityCache "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ++ lib.optional config.othrys.internal.llmAgentsCache "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        ++ lib.optional cfg.cachix.enable cfg.cachix.publicKey
        ++ cfg.extraTrustedPublicKeys;

      flake-registry = lib.mkIf (!cfg.globalRegistry) (lib.mkDefault "");
    };

    nix.optimise.automatic = lib.mkIf daemonManaged (lib.mkDefault true);

    nix.registry.nixpkgs.flake = lib.mkIf (pinnedNixpkgs != null) (lib.mkDefault pinnedNixpkgs);
    nix.nixPath = lib.mkIf (pinnedNixpkgs != null) ["nixpkgs=flake:nixpkgs"];
    nix.channel.enable = lib.mkIf (pinnedNixpkgs != null) (lib.mkDefault false);
    nixpkgs.flake = lib.mkIf (pinnedNixpkgs != null) {
      setFlakeRegistry = lib.mkDefault false;
      setNixPath = lib.mkDefault false;
    };

    programs.nh = lib.mkIf cfg.nh.enable {
      enable = true;
      inherit (cfg.nh) flake;
      clean = lib.mkIf nhCleans {
        enable = true;
        inherit (cfg.nh.clean) extraArgs;
      };
    };

    # nix-darwin warns when nh clean and nix.gc both run, so nix.gc is wired
    # only when nh is not handling retention.
    nix.gc = lib.mkIf (daemonManaged && !nhCleans) {
      inherit (cfg.gc) automatic;
      options = "--delete-older-than ${cfg.gc.olderThan}";
    };

    # system.stateVersion is left to the host. On nix-darwin it is an
    # integer with its own numbering, and cfg.stateVersion is the NixOS
    # release string that Home Manager reads through nix.nix.

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
