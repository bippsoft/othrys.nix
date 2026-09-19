# flake/checks/rustdesk.nix
# CORE. What the RustDesk module persists and what its launcher runs, read back
# from an evaluated host. The module once persisted a directory the client
# never writes to, and nothing but a reboot of a real host showed it.
{
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  host = rustdesk:
    hostConfig [
      functioningHost
      {
        # impermanence asserts on the disko layout. enableConfig = false keeps
        # disko from emitting filesystems that collide with the fixture's own, so
        # the two volumes impermanence marks as needed for boot are named here.
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
        };
        othrys.apps.rustdesk = {enable = true;} // rustdesk;
      }
    ];

  plain = host {};
  x11 = host {forceX11 = true;};

  user = plain.othrys.system.user.name;
  persisted = plain.environment.persistence.${plain.othrys.system.impermanence.persistRoot};
  pathOf = entry: entry.dirPath or entry.directory;
  userDirs = map pathOf persisted.users.${user}.directories;
  systemDirs = map pathOf persisted.directories;
  clientDir = "/home/${user}/.config/rustdesk";
  entries = cfg: cfg.home-manager.users.${user}.xdg.desktopEntries;
in
  mkExpectations "othrys-eval-rustdesk" {
    "the client's config directory is persisted for the primary user" = builtins.elem clientDir userDirs;
    "it is persisted with mode 0700" =
      builtins.any (entry: pathOf entry == clientDir && entry.mode == "0700") persisted.users.${user}.directories;
    "the unused /var/lib/rustdesk is not persisted" = !(builtins.elem "/var/lib/rustdesk" systemDirs);
    "no desktop entry is written by default" = !((entries plain) ? rustdesk);
    "forceX11 starts the launcher with GDK_BACKEND=x11" = (entries x11).rustdesk.exec == "env GDK_BACKEND=x11 rustdesk %u";
    "forceX11 keeps the rustdesk link handler" = (entries x11).rustdesk.mimeType == ["x-scheme-handler/rustdesk"];
  }
