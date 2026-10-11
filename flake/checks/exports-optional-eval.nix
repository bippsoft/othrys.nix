# flake/checks/exports-optional-eval.nix
# CORE. The five exports nixosModules.default leaves out, read back from
# evaluated hosts. The Home Manager adapter writes into the `home-manager`
# option namespace, the disk layout into `disko`, the secrets plumbing into
# `sops`, the impermanence adapter into `environment.persistence` and the
# Stylix adapter into `stylix`, and a write into a namespace no module
# declares fails whatever guards it. A host built from `default` alone
# therefore has to evaluate and declare none of the five. A host that imports
# each export beside its upstream module has to get what the export always
# wrote, and a host built from the aggregate has to have all five.
#
# Two shapes are refused by name. A host that turns impermanence on without
# the adapter would wipe its root and bind nothing back. A host with an
# account that Home Manager is to manage and no Home Manager adapter would
# create the account and skip every module that configures it.
{
  inputs,
  system,
  hostEval,
  impermanenceModules,
  stylixModules,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  diskoModules,
  secretsModules,
}: let
  inherit (inputs.nixpkgs) lib;
  evaluates = host: host.config.system.build.toplevel.drvPath != null;

  nix = {
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
  };

  # A primary account, with Home Manager left at its default, which is on.
  account = {
    othrys.system.users = {
      enable = true;
      # Bootstrap hash for "changeme", generated with mkpasswd -m yescrypt.
      initialHashedPassword = "$y$j9T$aiZuvauf85ZjB04z3seyG0$OKYG9I1g.vAp5IA48MlGzaVoB15gqWIL.k7lSni8fe8";
    };
  };

  # `default` and no upstream module at all, which is all hostEval adds. The
  # shape of a server.
  alone = hostEval [bootBase nix];

  # The account with no Home Manager adapter. Only its assertions and its
  # options are read, since the host is meant to be rejected.
  accountWithoutExport = hostEval [bootBase nix account];
  # The same account stated as one Home Manager does not manage, with a
  # module on that configures nothing but the user.
  accountUnmanaged = hostEval [
    bootBase
    nix
    account
    {
      othrys.system.users.homeManager.enable = false;
      othrys.apps.gh.enable = true;
    }
  ];
  skippedWarning = host: builtins.filter (lib.hasInfix "home-manager configuration was") host.config.warnings;

  # The Stylix adapter on a host with no Home Manager module. The adapter
  # writes one Home Manager option, behind a test for the namespace.
  stylixAlone = hostEval [bootBase nix stylixModules {othrys.system.stylix.enable = true;}];

  # The aggregate as the one othrys import of a host, with no upstream module
  # named beside it and a managed account. It is built here and not with
  # hostEval, which would put `default` in front of it.
  aggregate = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {inherit inputs;};
    modules = [inputs.self.nixosModules.full bootBase nix account];
  };
  # `default` beside the aggregate, which holds it already.
  aggregateTwice = hostEval [inputs.self.nixosModules.full bootBase nix account];
  homeNeedle = "nixosModules.home is not imported";

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

  # `default` with a managed account, so with Home Manager and its adapter
  # and none of the other four.
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
    "a host with `default` and no upstream module evaluates" = evaluates alone;
    "that host has no home-manager option namespace" = !(alone.options ? home-manager) && !(alone.config ? home-manager);
    "it has no environment.persistence option" = !(alone.options.environment ? persistence);
    "it has no disko, sops or stylix option namespace" = !(alone.options ? disko) && !(alone.options ? sops) && !(alone.options ? stylix);
    "it declares the Home Manager registry all the same" = alone.options.othrys.internal ? homeConfig;
    "it is not asked for the Home Manager adapter" = !rejectedWith homeNeedle alone.config;
    "its user is not managed" = !alone.config.othrys.system.users.homeManaged;

    "an account Home Manager is to manage is rejected without the adapter, by name" = rejectedWith homeNeedle accountWithoutExport.config;
    "the user of that host does not read as managed" = !accountWithoutExport.config.othrys.system.users.homeManaged;
    "an account Home Manager does not manage evaluates without the adapter" = evaluates accountUnmanaged && !(accountUnmanaged.options ? home-manager);
    "that account is not asked for the adapter" = !rejectedWith homeNeedle accountUnmanaged.config;
    "the skipped configuration is reported once, naming the module and the export" = builtins.length (skippedWarning accountUnmanaged) == 1 && builtins.all (w: lib.hasInfix "apps.gh" w && lib.hasInfix "othrys.nixosModules.home" w) (skippedWarning accountUnmanaged);
    "a managed account with the adapter is not asked for it" = !rejectedWith homeNeedle bare.config && bare.config.othrys.system.users.homeManaged;
    "the adapter hands the registry to the user" = bare.config.home-manager.users ? ${bare.config.othrys.system.user.name};

    "the Stylix adapter evaluates on a host with no Home Manager module" = evaluates stylixAlone && !(stylixAlone.options ? home-manager);
    "Stylix is on there" = stylixAlone.config.stylix.enable;

    "a host built from the aggregate alone evaluates" = evaluates aggregate;
    "the aggregate declares all five upstream namespaces" = aggregate.options ? home-manager && aggregate.options.environment ? persistence && aggregate.options ? disko && aggregate.options ? sops && aggregate.options ? stylix;
    "the aggregate manages the account through Home Manager" = aggregate.config.othrys.system.users.homeManaged && aggregate.config.home-manager.users ? alice;
    "the aggregate leaves the four switches off" = !aggregate.config.othrys.system.impermanence.enable && !aggregate.config.othrys.system.disko.enable && !aggregate.config.othrys.system.secrets.enable && !aggregate.config.othrys.system.stylix.enable;
    "the aggregate beside `default` evaluates" = evaluates aggregateTwice;

    "a managed host with no disko, sops-nix, Stylix or impermanence module evaluates" = evaluates bare;
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
