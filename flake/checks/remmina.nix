# flake/checks/remmina.nix
# CORE. What the Remmina module hands Home Manager and what it persists, read
# back from an evaluated host. The two directories hold the profiles and the key
# that decrypts their saved passwords, so losing either one or widening its mode
# goes unnoticed until a real host reboots.
{
  hostConfig,
  impermanenceModules,
  mkExpectations,
  functioningHost,
}: let
  host = extra:
    hostConfig ([
        functioningHost
        {
          imports = [impermanenceModules];
          # No disk layout is imported, so the wipe is given its device by hand and
          # the two volumes impermanence marks as needed for boot are named.
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
            impermanence = {
              enable = true;
              device = "/dev/disk/by-partlabel/root";
            };
            persistence.enable = true;
          };
        }
      ]
      ++ extra);

  enabled = {othrys.apps.remmina.enable = true;};

  plain = host [enabled];
  off = host [];
  # The host takes the login service back. The user name is read from the host
  # rather than written here, so the override follows functioningHost.
  withService = host [
    enabled
    ({config, ...}: {
      home-manager.users.${config.othrys.system.user.name}.services.remmina.systemdService.enable = true;
    })
  ];

  user = plain.othrys.system.user.name;
  pathOf = entry: entry.dirPath or entry.directory;
  userEntries = cfg: cfg.environment.persistence.${cfg.othrys.system.impermanence.persistRoot}.users.${user}.directories or [];
  persistedAt0700 = cfg: dir: builtins.any (entry: pathOf entry == dir && entry.mode == "0700") (userEntries cfg);
  persistedAtAll = cfg: dir: builtins.elem dir (map pathOf (userEntries cfg));
  configDir = "/home/${user}/.config/remmina";
  dataDir = "/home/${user}/.local/share/remmina";
  hm = cfg: cfg.home-manager.users.${user};
in
  mkExpectations "othrys-eval-remmina" {
    "Home Manager's remmina service is enabled for the primary user" = (hm plain).services.remmina.enable;
    "no remmina login service is written by default" = !((hm plain).systemd.user.services ? remmina);
    "a host that enables the login service gets it" = (hm withService).systemd.user.services ? remmina;
    "~/.config/remmina is persisted at mode 0700" = persistedAt0700 plain configDir;
    "~/.local/share/remmina is persisted at mode 0700" = persistedAt0700 plain dataDir;
    "with the module off, remmina is not enabled in Home Manager" = !(hm off).services.remmina.enable;
    "with the module off, ~/.config/remmina is not persisted" = !(persistedAtAll off configDir);
    "with the module off, ~/.local/share/remmina is not persisted" = !(persistedAtAll off dataDir);
  }
