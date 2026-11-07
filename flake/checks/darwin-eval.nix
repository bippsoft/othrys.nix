# flake/checks/darwin-eval.nix
# CORE. What the darwin exports write on a nix-darwin host. The account stays
# with macOS unless the host gives a uid, Nix defaults to Lix, the locale
# reaches the environment, a host that names a user and turns nothing on gets
# no account settings at all, and the home adapter hands the apps' user
# configuration to Home Manager with the darwin packages and paths.
{
  lib,
  darwinConfig,
  darwinBase,
  darwinHomeModules,
  darwinAppHost,
  mkExpectations,
  rejectedWith,
  inputs,
}: let
  account = {
    othrys.system.users = {
      enable = true;
      homeManager.enable = false;
    };
  };

  bare = darwinConfig [darwinBase];
  managed = darwinConfig [darwinBase account];
  known = darwinConfig [
    darwinBase
    account
    {othrys.system.users.uid = 502;}
    {othrys.system.shell.zsh.enable = true;}
  ];
  configured = darwinConfig [
    darwinBase
    account
    {
      othrys.system = {
        nix = {
          enable = true;
          stateVersion = "26.05";
        };
        locale = {
          enable = true;
          timezone = "Europe/Berlin";
          locale = "de_DE.UTF-8";
        };
        git = {
          enable = true;
          name = "Alice";
          email = "alice@example.com";
        };
      };
    }
  ];
  # Zsh with the Nix and clipboard presets left to their defaults, and an
  # editor of the host's choosing.
  shell = darwinConfig [
    darwinBase
    {
      othrys.system.shell.zsh.enable = true;
      othrys.system.defaultEditor = "nvim";
    }
  ];
  zshAliases = shell.othrys.internal.homeConfig."system.shell.zsh".programs.zsh.shellAliases;
  # A nixpkgs instance passed in with allowUnfree off while othrys.system.nix
  # allows it, which the module refuses as it does on NixOS.
  externalPkgs = darwinConfig [
    darwinBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
        allowUnfree = true;
      };
      nixpkgs.pkgs = import inputs.nixpkgs {system = "aarch64-darwin";};
    }
  ];
  # Every darwin app on, with Home Manager and the home adapter, read back
  # from the user's Home Manager configuration.
  apps = darwinConfig [darwinBase darwinAppHost];
  home = apps.home-manager.users.alice;
  managedHome = darwinConfig [
    darwinBase
    darwinHomeModules
    {
      othrys.system.users.enable = true;
      # Home Manager's state version comes through the registry from here.
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
    }
  ];
  # The registry still collects entries without the home adapter, which is
  # what the adapter hands to Home Manager on a host that imports it.
  homeEntries = builtins.attrNames configured.othrys.internal.homeConfig;
  withHomeManager = darwinConfig [darwinBase {othrys.system.users.enable = true;}];
in
  mkExpectations "othrys-eval-darwin" {
    "a host with only a user named sets no primary user" = bare.system.primaryUser == null;
    "a host with only a user named writes no account" = !(bare.users.users ? alice);
    "a Mac runs a graphical session by default" = bare.othrys.desktop.graphical;
    "EDITOR defaults to vim" = bare.environment.variables.EDITOR == "vim";

    "the account makes alice the primary user" = managed.system.primaryUser == "alice";
    "the account's home is under /Users" = managed.users.users.alice.home == "/Users/alice";
    "an account without a uid stays out of knownUsers" = !(builtins.elem "alice" managed.users.knownUsers);
    "an account without a uid gets no shell from othrys" = managed.users.users.alice.shell == null;

    "a uid hands the account to nix-darwin" = builtins.elem "alice" known.users.knownUsers && known.users.users.alice.uid == 502;
    "a known account takes the zsh login shell" = (known.users.users.alice.shell.pname or null) == "zsh";
    "zsh is enabled for the login shell" = known.programs.zsh.enable;

    "Nix defaults to Lix" = lib.getName configured.nix.package == "lix";
    "nix-darwin keeps managing Nix" = configured.nix.enable;
    "flakes are enabled" = builtins.elem "flakes" configured.nix.settings.experimental-features;
    "the store is optimised by the scheduled job, not on every write" = configured.nix.optimise.automatic && !(configured.nix.settings.auto-optimise-store or false);
    "nixpkgs is pinned in the registry" = configured.nix.registry.nixpkgs.flake.outPath == inputs.nixpkgs.outPath;
    "the timezone is set" = configured.time.timeZone == "Europe/Berlin";
    "the locale reaches LANG" = configured.environment.variables.LANG == "de_DE.UTF-8";
    # The nix entry carries the Home Manager state version and is withheld
    # while Home Manager manages no account.
    "git hands its user configuration to the registry" = builtins.elem "system.git" homeEntries;
    "nix withholds its entry from an account Home Manager does not manage" = !(builtins.elem "system.nix" homeEntries);

    "a known account is visible and gets a home directory" = !known.users.users.alice.isHidden && known.users.users.alice.createHome;
    "the default bash login shell is the interactive build" = (darwinConfig [darwinBase account {othrys.system.users.uid = 502;}]).users.users.alice.shell.pname == "bash-interactive";
    "the othrys pin replaces nix-darwin's own registry and NIX_PATH entries" = !configured.nixpkgs.flake.setFlakeRegistry && !configured.nixpkgs.flake.setNixPath;
    "git is installed system-wide" = builtins.any (p: lib.getName p == "git") configured.environment.systemPackages;
    "EDITOR and VISUAL follow defaultEditor" = shell.environment.variables.EDITOR == "nvim" && shell.environment.variables.VISUAL == "nvim";
    "the rebuild alias runs darwin-rebuild" = zshAliases.rebuild == "sudo darwin-rebuild switch --flake .";
    "there is no rebuild-test alias on darwin" = !(zshAliases ? rebuild-test);
    "the clipboard preset is off on a Mac" = !shell.othrys.system.shell.zsh.aliasPresets.clipboard;
    "an external nixpkgs that disagrees on allowUnfree is refused" = rejectedWith "nixpkgs.pkgs is defined externally" externalPkgs;
    "the home adapter gives Home Manager the account's home" = home.home.homeDirectory == "/Users/alice";
    "the home adapter hands the user the registry" = home.programs.nixvim.enable && home.programs.gh.enable;
    "the essential user tools reach the darwin user" = builtins.any (p: lib.getName p == "just") home.home.packages;
    "an account with Home Manager and the adapter is accepted" = !(rejectedWith "is not imported" managedHome);
    "Ghostty takes the darwin build" = lib.getName home.programs.ghostty.package == "ghostty-bin";
    "kitty's control socket sits in the per-user TMPDIR" = lib.hasPrefix "unix:\${TMPDIR}/" home.programs.kitty.settings.listen_on;
    "VSCodium finds nixvim under the darwin key" = home.programs.vscodium.profiles.default.userSettings ? "vscode-neovim.neovimExecutablePaths.darwin";
    "the assistants are not told they run on NixOS" = !apps.othrys.apps.ai.context.nixos.enable && !(lib.hasInfix "NixOS" apps.othrys.apps.ai.context.text);
    "yazi pulls no Wayland clipboard on a Mac" = !(builtins.any (p: lib.getName p == "wl-clipboard") home.home.packages);
    "an account with Home Manager on and no home adapter is refused" = rejectedWith "darwinModules.home is not imported" withHomeManager;
  }
