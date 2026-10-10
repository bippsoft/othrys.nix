# flake/checks/persistence-eval.nix
# CORE. What the app and desktop modules persist, read back from two evaluated
# hosts. impermanence reads users.users.<name>.home for every entry under
# `users`, so a per-user write guarded on impermanence alone fails evaluation
# on a host that has impermanence and no managed account, and no other
# fixture has that shape. The managed host reads back the modes of the
# directories that hold tokens and keys, the directories that are no longer
# persisted because Home Manager owns their contents, and the paths that were
# once left on the ephemeral root.
{
  hostConfig,
  mkExpectations,
  bootBase,
  functioningHost,
  appDesktopModules,
}: let
  impermanence = {
    # impermanence asserts on the disko layout. enableConfig = false keeps
    # disko from emitting filesystems that collide with the fixture's own,
    # so the two volumes impermanence marks as needed for boot are named.
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
    othrys = {
      system = {
        disko = {
          enable = true;
          device = "/dev/disk/by-id/example";
        };
        impermanence.enable = true;
        persistence.enable = true;
        shell.zsh.enable = true;
      };
      # The secrets module, which the app fixture enables, decrypts with the
      # persisted ssh host key on an impermanence host and requires sshd.
      services.ssh = {
        enable = true;
        server.enable = true;
      };
      hardware.wireless = {
        bluetooth.enable = true;
        wifi.enable = true;
      };
    };
  };

  # A declared user name and no managed account, the shape eval-host-server
  # covers for the server modules, here with every app and desktop module on.
  unmanaged = hostConfig [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
    }
    impermanence
    appDesktopModules
  ];

  managed = hostConfig [
    functioningHost
    impermanence
    appDesktopModules
  ];

  rootOf = cfg: cfg.environment.persistence.${cfg.othrys.system.impermanence.persistRoot};
  user = managed.othrys.system.user.name;
  persisted = rootOf managed;
  home = "/home/${user}";
  pathOf = entry: entry.dirPath or entry.directory;
  userDirs = persisted.users.${user}.directories;
  userDirPaths = map pathOf userDirs;
  userFiles = map (entry: entry.filePath or entry.file) persisted.users.${user}.files;
  systemDirs = persisted.directories;
  systemDirPaths = map pathOf systemDirs;
  modeOf = dirs: path: let
    hits = builtins.filter (entry: pathOf entry == path) dirs;
  in
    if hits == []
    then null
    else (builtins.head hits).mode;
  userMode = rel: modeOf userDirs "${home}/${rel}";
  persistsUser = rel: builtins.elem "${home}/${rel}" userDirPaths;
in
  mkExpectations "othrys-eval-persistence" {
    "a host with impermanence and no managed account evaluates" = unmanaged.system.build.toplevel.drvPath != null;
    "it persists nothing under users" = (rootOf unmanaged).users == {};
    "the managed host evaluates" = managed.system.build.toplevel.drvPath != null;

    "gh is persisted at 0700" = userMode ".config/gh" == "0700";
    "Signal is persisted at 0700" = userMode ".config/Signal" == "0700";
    "discord is persisted at 0700" = userMode ".config/discord" == "0700";
    "vesktop is persisted at 0700" = userMode ".config/vesktop" == "0700";
    "Plexamp is persisted at 0700" = userMode ".config/Plexamp" == "0700";
    "PrismLauncher is persisted at 0700" = userMode ".local/share/PrismLauncher" == "0700";
    "claude-code is persisted at 0700" = userMode ".claude" == "0700";
    "OBS is persisted at 0700" = userMode ".config/obs-studio" == "0700";
    "the bluetooth tree is persisted at 0700" = modeOf systemDirs "/var/lib/bluetooth" == "0700";

    "the hyprland config directory is not persisted" = !persistsUser ".config/hypr";
    "the ashell config directory is not persisted" = !persistsUser ".config/ashell";

    "nvim sessions are persisted" = persistsUser ".local/state/nvim";
    "localsend state is persisted" = persistsUser ".local/share/localsend_app";
    "r2modman profiles are persisted" = persistsUser ".config/r2modmanPlus-local";
    "the direnv allow database is persisted" = persistsUser ".local/share/direnv";

    "zsh history is persisted through its directory" = persistsUser ".local/share/zsh";
    "the history file itself is not persisted" = !(builtins.elem "${home}/.zsh_history" userFiles);
    "HISTFILE points under the persisted directory" =
      managed.home-manager.users.${user}.programs.zsh.history.path == "$HOME/.local/share/zsh/history";

    "NetworkManager connections are persisted" = modeOf systemDirs "/etc/NetworkManager/system-connections" == "0700";
    "NetworkManager state is persisted" = builtins.elem "/var/lib/NetworkManager" systemDirPaths;
    "/etc/NetworkManager itself is not persisted" = !(builtins.elem "/etc/NetworkManager" systemDirPaths);
  }
