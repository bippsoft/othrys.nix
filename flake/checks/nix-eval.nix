# flake/checks/nix-eval.nix
# CORE. What the nix module trusts and pins, read back from evaluated hosts.
# A wheel user was a trusted Nix user and so root over the host past every
# other control, a third-party cache was trusted on every host, and an
# enabled cachix with empty values was skipped without a word. None of that
# fails evaluation.
{
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  inputs,
}: let
  host = extra:
    hostConfig [
      bootBase
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
      }
      extra
    ];
  settings = cfg: cfg.nix.settings;

  plain = host {};
  community = host {othrys.system.nix.communityCache = true;};
  admins = host {othrys.system.nix.trustedUsers = ["root" "@wheel"];};
  cachix = host {
    othrys.system.nix.cachix = {
      enable = true;
      name = "example";
      publicKey = "example.cachix.org-1:AAAA";
    };
  };
  cachixEmpty = host {othrys.system.nix.cachix.enable = true;};
  withUser = hostConfig [functioningHost];
  nonAdmin = hostConfig [functioningHost {othrys.system.users.wheel = false;}];
in
  mkExpectations "othrys-eval-nix" {
    "only root is a trusted user by default" = builtins.all (u: u == "root") (settings plain).trusted-users;
    "a host can trust its administrators" = builtins.elem "@wheel" (settings admins).trusted-users;
    "the community cache is not trusted by default" = !builtins.any (s: builtins.match ".*nix-community.*" s != null) (settings plain).substituters && !builtins.any (k: builtins.match "nix-community.*" k != null) (settings plain).trusted-public-keys;
    "the community cache is trusted when asked" = builtins.elem "https://nix-community.cachix.org" (settings community).substituters;
    "cache.nixos.org stays" = builtins.elem "https://cache.nixos.org" (settings plain).substituters;
    "an enabled cachix adds its substituter and key" = builtins.elem "https://example.cachix.org" (settings cachix).substituters && builtins.elem "example.cachix.org-1:AAAA" (settings cachix).trusted-public-keys;
    "an enabled cachix with empty values is rejected" = rejectedWith "set name and publicKey" cachixEmpty;
    "the registry pins nixpkgs to the host's input" = plain.nix.registry.nixpkgs.flake == inputs.nixpkgs;
    "NIX_PATH follows the registry" = builtins.elem "nixpkgs=flake:nixpkgs" plain.nix.nixPath;
    "the primary user is in wheel by default" = builtins.elem "wheel" withUser.users.users.alice.extraGroups;
    "a host can keep its primary user out of wheel" = !builtins.elem "wheel" nonAdmin.users.users.alice.extraGroups;
  }
