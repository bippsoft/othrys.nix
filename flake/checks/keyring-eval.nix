# flake/checks/keyring-eval.nix
# CORE. The Secret Service provider each setting of othrys.desktop.keyring
# selects, read back from evaluated hosts. Two providers running side by
# side, a pass store with no key to encrypt to and a store without a
# password on an unencrypted disk all evaluate cleanly unless the module
# refuses them, so each is compared here with what the module documents.
{
  lib,
  hostConfig,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  accountNoHomeManager,
}: let
  host = extra:
    hostConfig [
      functioningHost
      extra
    ];

  user = "alice";
  home = cfg: cfg.home-manager.users.${user};

  # A placeholder in the shape of a fingerprint. No key is read during
  # evaluation.
  fingerprint = "0123456789ABCDEF0123456789ABCDEF01234567";
  store = "/home/${user}/.local/share/password-store";

  greeter = {othrys.desktop.login.enable = true;};
  hyprland = {
    imports = [greeter];
    othrys.desktop.compositors.hyprland.enable = true;
  };
  niri = {
    imports = [greeter];
    othrys.desktop.compositors.niri.enable = true;
  };
  pass = {
    othrys.desktop.keyring = {
      provider = "pass";
      pass.gpgKey = fingerprint;
    };
  };
  passwordless = {othrys.desktop.keyring.passwordless = true;};
  # What a host that set LUKS up by hand declares.
  luks = {boot.initrd.luks.devices.cryptroot.device = "/dev/disk/by-partlabel/root";};

  default = host hyprland;
  passHyprland = host {imports = [hyprland pass];};
  # niri-flake enables gnome-keyring on a niri host itself, so this is the
  # host that shows pass still ends up as the only provider.
  passNiri = host {imports = [niri pass];};
  passNoKey = host {
    imports = [hyprland];
    othrys.desktop.keyring.provider = "pass";
  };
  passNoHomeManager = hostConfig [
    accountNoHomeManager
    pass
    {othrys.desktop.graphical = true;}
  ];
  passOtherDirectory = host {
    imports = [hyprland pass];
    othrys.desktop.keyring.pass.directory = ".password-store";
  };

  passwordlessPlain = host {imports = [hyprland passwordless];};
  passwordlessLuks = host {imports = [hyprland passwordless luks];};
  passwordlessNiri = host {imports = [niri passwordless luks];};
  passwordlessAccepted = host {
    imports = [hyprland passwordless];
    othrys.desktop.keyring.allowUnencryptedDisk = true;
  };
  passwordlessPass = host {imports = [hyprland pass passwordless luks];};

  headless = hostConfig [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
    }
  ];

  # An impermanence host, in the shape eval-persistence uses. disko's own
  # filesystems are left out, so the two volumes impermanence needs for boot
  # are named.
  impermanence = {
    disko.enableConfig = false;
    fileSystems = {
      "/nix" = {
        device = "/dev/disk/by-label/nix";
        fsType = "btrfs";
      };
      "/persist" = {
        device = "/dev/disk/by-label/persist";
        fsType = "btrfs";
      };
    };
    othrys.system = {
      disko = {
        enable = true;
        device = "/dev/disk/by-id/example";
      };
      impermanence.enable = true;
      persistence.enable = true;
      shell.zsh.enable = true;
    };
  };
  persistedDefault = host {imports = [hyprland impermanence];};
  persistedPass = host {imports = [hyprland pass impermanence];};
  userDirs = cfg: cfg.environment.persistence.${cfg.othrys.system.impermanence.persistRoot}.users.${user}.directories;
  pathOf = entry: entry.dirPath or entry.directory;
  persistedAt = cfg: rel: mode: builtins.any (entry: pathOf entry == "/home/${user}/${rel}" && entry.mode == mode) (userDirs cfg);
  persists = cfg: rel: builtins.any (entry: pathOf entry == "/home/${user}/${rel}") (userDirs cfg);

  gnomeKeyring = cfg: cfg.services.gnome.gnome-keyring.enable;
  greeterUnlocks = cfg: cfg.security.pam.services.greetd.enableGnomeKeyring;
  passService = cfg: (home cfg).services.pass-secret-service;
  passwordStore = cfg: (home cfg).programs.password-store;
  activation = cfg: (home cfg).home.activation;

  unnamed = "othrys.desktop.keyring.pass.gpgKey";
  needsHomeManager = "runs pass-secret-service as a Home Manager user service";
  needsEncryption = "othrys.desktop.keyring.allowUnencryptedDisk";
  notWithPass = "othrys.desktop.keyring.passwordless creates a gnome-keyring store";
  refusal = "othrys.desktop.keyring";
in
  mkExpectations "othrys-eval-keyring" {
    "the provider is gnome-keyring unless the host says otherwise" = default.othrys.desktop.keyring.provider == "gnome-keyring" && gnomeKeyring default;
    "the default host still has the greeter unlock the keyring" = greeterUnlocks default;
    "the default host is not passwordless" = !default.othrys.desktop.keyring.passwordless && !(activation default ? othrysPasswordlessKeyring);
    "the default host runs no pass service" = !(passService default).enable && !(passwordStore default).enable;
    "the default host is accepted" = !rejectedWith refusal default;

    "pass runs pass-secret-service for the primary user on hyprland" = (passService passHyprland).enable;
    "pass runs pass-secret-service for the primary user on niri" = (passService passNiri).enable;
    "pass enables the password store on hyprland" = (passwordStore passHyprland).enable;
    "pass enables the password store on niri" = (passwordStore passNiri).enable;
    "pass and the service are pointed at one store" = (passwordStore passHyprland).settings.PASSWORD_STORE_DIR == store && (passService passHyprland).storePath == store;
    "the store directory follows the option" = (passService passOtherDirectory).storePath == "/home/${user}/.password-store";
    "pass turns gnome-keyring off on hyprland" = !gnomeKeyring passHyprland;
    "pass turns gnome-keyring off on niri" = !gnomeKeyring passNiri;
    "pass leaves the greeter alone" = !greeterUnlocks passHyprland && !greeterUnlocks passNiri;
    "pass initialises the store for the key when it has none" = let
      step = (activation passHyprland).othrysPassStore;
    in
      lib.hasInfix "store=${lib.escapeShellArg store}\n" step.data && lib.hasInfix "! -e \"$store/.gpg-id\"" step.data && lib.hasInfix "-gpg-id \"$store/.gpg-id\"" step.data && step.after == ["writeBoundary"];
    "pass with a key is accepted" = !rejectedWith refusal passHyprland && !rejectedWith refusal passNiri;
    "pass without a key is rejected" = rejectedWith unnamed passNoKey;
    "pass without a key still turns gnome-keyring off" = !gnomeKeyring passNoKey;
    "pass without Home Manager is rejected" = rejectedWith needsHomeManager passNoHomeManager;

    "passwordless keeps gnome-keyring as the provider" = gnomeKeyring passwordlessLuks && gnomeKeyring passwordlessNiri;
    "passwordless writes the keyring when none exists" = let
      step = (activation passwordlessLuks).othrysPasswordlessKeyring;
    in
      lib.hasInfix "! -e \"$keyrings/login.keyring\"" step.data
      && lib.hasInfix "! -e \"$keyrings/Default_keyring.keyring\"" step.data
      && lib.hasInfix "-Default_keyring.keyring \"$keyrings/Default_keyring.keyring\"" step.data
      && lib.hasInfix "-keyring-default \"$keyrings/default\"" step.data
      && lib.hasInfix "install -m 0600" step.data
      && lib.hasInfix "mkdir -p -m 0700" step.data
      && step.after == ["writeBoundary"];
    "passwordless leaves the greeter with nothing to unlock" = !greeterUnlocks passwordlessLuks && !greeterUnlocks passwordlessNiri;
    "passwordless on a plain disk is rejected" = rejectedWith needsEncryption passwordlessPlain;
    "passwordless with a LUKS device is accepted" = !rejectedWith refusal passwordlessLuks && !rejectedWith refusal passwordlessNiri;
    "passwordless on a plain disk is accepted with the escape option" = !rejectedWith refusal passwordlessAccepted;
    "passwordless with pass is rejected" = rejectedWith notWithPass passwordlessPass;
    "passwordless with pass writes no keyring" = !(activation passwordlessPass ? othrysPasswordlessKeyring);

    "gnome-keyring persists its keyrings at 0700" = persistedAt persistedDefault ".local/share/keyrings" "0700";
    "pass persists its store at 0700" = persistedAt persistedPass ".local/share/password-store" "0700";
    "pass persists no gnome-keyring store" = !persists persistedPass ".local/share/keyrings";

    "a headless host has no provider" = !headless.othrys.desktop.keyring.enable && !gnomeKeyring headless;
    "a headless host has no Home Manager user" = headless.home-manager.users == {};
    "a headless host is accepted" = !rejectedWith refusal headless;
  }
