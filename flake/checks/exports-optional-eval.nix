# flake/checks/exports-optional-eval.nix
# CORE. The three exports nixosModules.default leaves out beside the Stylix
# adapter, read back from evaluated hosts. The disk layout writes into the
# `disko` option namespace, the secrets plumbing into `sops` and the
# impermanence adapter into `environment.persistence`, and a write into a
# namespace no module declares fails whatever guards it. A host built from
# `default` and home-manager alone therefore has to evaluate and declare
# none of the three. A host that imports each export beside its upstream
# module has to get what the export always wrote, and a host that turns
# impermanence on without the adapter has to be told so, since it would wipe
# its root and bind nothing back.
{
  hostEval,
  impermanenceModules,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  diskoModules,
  secretsModules,
}: let
  evaluates = host: host.config.system.build.toplevel.drvPath != null;

  # Impermanence on a device named by hand, with the two volumes it marks as
  # needed for boot.
  wipedByHand = {
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
    othrys.system.impermanence = {
      enable = true;
      device = "/dev/disk/by-partlabel/root";
    };
  };

  # The disko layout. enableConfig = false keeps disko from emitting a root
  # filesystem that collides with the one the fixture base carries, and the
  # declared devices are read back all the same.
  layout = {
    imports = [diskoModules];
    disko.enableConfig = false;
    othrys.system.disko = {
      enable = true;
      device = "/dev/disk/by-id/example";
    };
  };

  secrets = {
    imports = [secretsModules];
    othrys.system.secrets.enable = true;
  };

  # `default` and home-manager, which is all hostEval adds.
  bare = hostEval [functioningHost];
  # The impermanence adapter and no disk layout.
  bareWiped = hostEval [functioningHost impermanenceModules wipedByHand];
  # Impermanence on with neither the adapter nor the impermanence module.
  # Only its assertions are read, since the host is meant to be rejected.
  wipedWithoutAdapter = hostEval [functioningHost wipedByHand];
  # The adapter with the system-critical set on, for the entries it binds.
  # Only environment.persistence is read from it.
  bound = hostEval [functioningHost impermanenceModules wipedByHand {othrys.system.persistence.enable = true;}];
  boundRoot = bound.config.environment.persistence."/persist";
  pathOf = entry: entry.dirPath or entry.directory;
  entryAt = path: entries: builtins.filter (entry: pathOf entry == path) entries;
  boundUser = boundRoot.users.${bound.config.othrys.system.user.name};

  # The adapter imported and impermanence left off.
  adapterOff = hostEval [functioningHost impermanenceModules];

  # Both exports imported and left off, the shape every host had while
  # `default` carried them.
  importedOff = hostEval [functioningHost diskoModules secretsModules];

  withLayout = hostEval [functioningHost layout];
  withLayoutRenamed = hostEval [functioningHost layout {othrys.system.disko.luks.name = "vault";}];

  withSecrets = hostEval [functioningHost secrets];
  # The secrets plumbing decrypts with the persisted ssh host key on an
  # impermanence host, so the persistence module and sshd are on beside it.
  withSecretsWiped = hostEval [
    bootBase
    impermanenceModules
    wipedByHand
    secrets
    {
      othrys.system.persistence.enable = true;
      othrys.services.ssh = {
        enable = true;
        server.enable = true;
      };
    }
  ];

  wipeUnit = host: host.config.boot.initrd.systemd.services.root-wipe;
  needle = "othrys.system.impermanence: set device";
  adapterNeedle = "nixosModules.impermanence is not imported";
in
  mkExpectations "othrys-eval-optional-exports" {
    "a host with no disko, sops-nix, Stylix or impermanence module evaluates" = evaluates bare;
    "that host has no environment.persistence option" = !(bare.options.environment ? persistence);
    "that host declares the persistence registry all the same" = bare.options.othrys.internal ? persist;
    "that host is not asked for the impermanence adapter" = !rejectedWith adapterNeedle bare.config;
    "that host has no disko option namespace" = !(bare.config ? disko) && !(bare.options ? disko);
    "that host has no sops option namespace" = !(bare.config ? sops) && !(bare.options ? sops);
    "that host has no stylix option namespace" = !(bare.config ? stylix);
    "that host declares neither othrys.system.disko nor othrys.system.secrets" = !(bare.options.othrys.system ? disko) && !(bare.options.othrys.system ? secrets);
    "the impermanence device is unset there" = bare.config.othrys.system.impermanence.device == null;

    "impermanence evaluates there on a device named by hand" = evaluates bareWiped && !(bareWiped.config ? disko);
    "the wipe unit waits for that device" = (wipeUnit bareWiped).requires == ["dev-disk-by\\x2dpartlabel-root.device"];
    "that host is not asked for a device" = !rejectedWith needle bareWiped.config;
    "that host is not asked for the adapter it imports" = !rejectedWith adapterNeedle bareWiped.config;

    "impermanence without the adapter is rejected by name" = rejectedWith adapterNeedle wipedWithoutAdapter.config;
    "the adapter declares no persist root while impermanence is off" = adapterOff.config.environment.persistence == {};
    "the adapter binds the system-critical directories with their owner and mode" = builtins.all (path: builtins.any (entry: entry.user == "root" && entry.group == "root" && entry.mode == "0755") (entryAt path boundRoot.directories)) ["/var/lib/systemd" "/var/lib/nixos" "/var/log"];
    "the adapter binds the sudo lecture state at 0700" = builtins.any (entry: entry.mode == "0700") (entryAt "/var/db/sudo/lectured" boundRoot.directories);
    "the adapter binds /etc/machine-id and /etc/adjtime as files" = builtins.all (path: builtins.elem path (map (entry: entry.filePath or entry.file) boundRoot.files)) ["/etc/machine-id" "/etc/adjtime"];
    "the adapter hides the mounts of the system-critical set" = boundRoot.hideMounts;
    "the adapter binds the user's ssh directory at 0700" = builtins.any (entry: entry.mode == "0700") (entryAt "/home/alice/.ssh" boundUser.directories);
    "the adapter binds the XDG user directories" = builtins.all (dir: entryAt "/home/alice/${dir}" boundUser.directories != []) ["Desktop" "Documents" "Downloads" "Music" "Pictures" "Videos" "Public" "Templates"];
    "the adapter binds the shell history file" = builtins.elem "/home/alice/.bash_history" (map (entry: entry.filePath or entry.file) boundUser.files);

    "a host that imports both exports and enables neither evaluates" = evaluates importedOff;
    "the layout declares no disk while it is off" = importedOff.config.disko.devices.disk == {};
    "the layout leaves the impermanence device unset while it is off" = importedOff.config.othrys.system.impermanence.device == null;

    "the layout declares its disk on the device the host names" = withLayout.config.disko.devices.disk.main.device == "/dev/disk/by-id/example";
    "the disk carries a GPT partition table" = withLayout.config.disko.devices.disk.main.content.type == "gpt";
    "the layout hands impermanence its LUKS mapping" = withLayout.config.othrys.system.impermanence.device == "/dev/mapper/cryptroot";
    "the mapping follows the LUKS name" = withLayoutRenamed.config.othrys.system.impermanence.device == "/dev/mapper/vault";
    "the layout turns fstrim on" = withLayout.config.services.fstrim.enable;

    "a host with the secrets export evaluates" = evaluates withSecrets;
    "sops-nix is pointed at the age key" = withSecrets.config.sops.age.keyFile == "/var/lib/sops-nix/key.txt";
    "sops-nix is pointed at the ssh host key" = withSecrets.config.sops.age.sshKeyPaths == ["/etc/ssh/ssh_host_ed25519_key"];
    "sops-nix generates the age key" = withSecrets.config.sops.age.generateKey;
    "both keys move under the persist root on an impermanence host" = withSecretsWiped.config.sops.age.keyFile == "/persist/var/lib/sops-nix/key.txt" && withSecretsWiped.config.sops.age.sshKeyPaths == ["/persist/etc/ssh/ssh_host_ed25519_key"];
  }
