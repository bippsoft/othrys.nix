# flake/checks/exports-optional-eval.nix
# CORE. The two exports nixosModules.default leaves out beside the Stylix
# adapter, read back from evaluated hosts. The disk layout writes into the
# `disko` option namespace and the secrets plumbing into `sops`, and a write
# into a namespace no module declares fails whatever guards it. A host built
# from `default`, home-manager and impermanence alone therefore has to
# evaluate, declare neither namespace and still run the root wipe on a
# device it names itself. A host that imports each export beside its
# upstream module has to get what the export always wrote.
{
  hostEval,
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

  # `default`, home-manager and impermanence, which is all hostEval adds.
  bare = hostEval [functioningHost];
  bareWiped = hostEval [functioningHost wipedByHand];

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
in
  mkExpectations "othrys-eval-optional-exports" {
    "a host with no disko, sops-nix or Stylix module evaluates" = evaluates bare;
    "that host has no disko option namespace" = !(bare.config ? disko) && !(bare.options ? disko);
    "that host has no sops option namespace" = !(bare.config ? sops) && !(bare.options ? sops);
    "that host has no stylix option namespace" = !(bare.config ? stylix);
    "that host declares neither othrys.system.disko nor othrys.system.secrets" = !(bare.options.othrys.system ? disko) && !(bare.options.othrys.system ? secrets);
    "the impermanence device is unset there" = bare.config.othrys.system.impermanence.device == null;

    "impermanence evaluates there on a device named by hand" = evaluates bareWiped && !(bareWiped.config ? disko);
    "the wipe unit waits for that device" = (wipeUnit bareWiped).requires == ["dev-disk-by\\x2dpartlabel-root.device"];
    "that host is not asked for a device" = !rejectedWith needle bareWiped.config;

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
