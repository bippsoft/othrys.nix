# flake/checks/types-eval.nix
# CORE. What the option types and the named assertions refuse, read back from
# evaluated hosts. A git identity is required only where Home Manager writes
# it. An interface that names a bridge or a vlan nobody declares is rejected
# with the name in the message. The home directory an account declares
# reaches the XDG directories and the persisted home. A user name or a theme
# outside the accepted set is refused by the option type.
{
  hostConfig,
  impermanenceModules,
  mkExpectations,
  rejectedWith,
  bootBase,
  functioningHost,
  inputs,
}: let
  inherit (inputs.nixpkgs) lib;

  nix = {
    othrys.system.nix = {
      enable = true;
      stateVersion = "26.05";
    };
  };

  # A declared user name and no managed account.
  headless = extra: hostConfig [bootBase nix extra];

  # A managed account that states no git identity of its own, which
  # functioningHost would supply.
  managed = extra:
    hostConfig [
      bootBase
      nix
      {
        othrys.system.users = {
          enable = true;
          # Bootstrap hash for "changeme", generated with mkpasswd -m yescrypt.
          initialHashedPassword = "$y$j9T$aiZuvauf85ZjB04z3seyG0$OKYG9I1g.vAp5IA48MlGzaVoB15gqWIL.k7lSni8fe8";
        };
      }
      extra
    ];

  gitNeedle = "set othrys.system.git.name and othrys.system.git.email";
  gitHeadless = headless {othrys.system.git.enable = true;};
  gitAnonymous = managed {othrys.system.git.enable = true;};
  gitNameOnly = managed {
    othrys.system.git = {
      enable = true;
      name = "alice";
    };
  };
  gitNoHomeManager = managed {
    othrys.system.users.homeManager.enable = false;
    othrys.system.git.enable = true;
  };
  gitNamed = hostConfig [functioningHost];

  network = interfaces:
    headless {
      othrys.system.networking = {
        enable = true;
        inherit interfaces;
        bridges.br-lan.address = ["10.0.0.1/24"];
        vlans.vlan100 = {
          id = 100;
          address = ["10.100.0.1/24"];
        };
      };
    };
  bridgeNeedle = "names a bridge that is not declared";
  vlanNeedle = "names a vlan that is not declared";
  networkValid = network {
    lan-port = {
      match = "enp1s0f1";
      bridge = "br-lan";
      requiredForOnline = "enslaved";
    };
    trunk = {
      match = "enp1s0f2";
      dhcp = false;
      vlans = ["vlan100"];
    };
  };
  networkBadBridge = network {
    lan-port = {
      match = "enp1s0f1";
      bridge = "br-missing";
    };
  };
  networkBadVlan = network {
    trunk = {
      match = "enp1s0f2";
      vlans = ["vlan100" "vlan200"];
    };
  };
  # A bridge and a vlan declared as raw netdevs, the route the module header
  # gives for a topology it does not model.
  networkRawNetdevs = headless {
    othrys.system.networking = {
      enable = true;
      interfaces.lan-port = {
        match = "enp1s0f1";
        bridge = "br-raw";
        vlans = ["vlan300"];
      };
    };
    systemd.network.netdevs = {
      "30-br-raw".netdevConfig = {
        Kind = "bridge";
        Name = "br-raw";
      };
      "30-vlan300" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan300";
        };
        vlanConfig.Id = 300;
      };
    };
  };
  messageOf = needle: cfg: lib.concatMapStrings (a: a.message) (builtins.filter (a: !a.assertion && lib.hasInfix needle a.message) cfg.assertions);

  # A managed account whose home is outside /home, on a root that is wiped at
  # boot so the persisted home can be read back beside the XDG directories.
  relocated = hostConfig [
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
      users.users.alice.home = "/srv/alice";
    }
  ];
  userDirs = relocated.home-manager.users.alice.xdg.userDirs;
  persistedDirs = map (entry: entry.dirPath or entry.directory) relocated.environment.persistence.${relocated.othrys.system.impermanence.persistRoot}.users.alice.directories;

  # A type refuses a value while the option is being read, which aborts the
  # evaluation, so each value is read under tryEval instead of through an
  # assertion. bootBase already names the user, hence the mkForce.
  userNamed = name: builtins.tryEval (hostConfig [bootBase {othrys.system.user.name = lib.mkForce name;}]).othrys.system.user.name;
  themed = theme: builtins.tryEval (hostConfig [functioningHost {othrys.apps.ai.claude-code.theme = theme;}]).othrys.apps.ai.claude-code.theme;
in
  mkExpectations "othrys-eval-types" {
    "git without an identity is rejected on a managed host" = rejectedWith gitNeedle gitAnonymous;
    "git with a name and no email is rejected too" = rejectedWith gitNeedle gitNameOnly;
    "git with both is accepted" = !rejectedWith gitNeedle gitNamed;
    "the identity reaches the Home Manager git settings" = let
      inherit (gitNamed.home-manager.users.alice.programs.git.settings) user;
    in
      user.name == "alice" && user.email == "alice@example.com";
    "git without an identity is accepted on a headless host" = !rejectedWith gitNeedle gitHeadless;
    "that headless host evaluates" = gitHeadless.system.build.toplevel.drvPath != null;
    "git without an identity is accepted where Home Manager is off" = !rejectedWith gitNeedle gitNoHomeManager;

    "a declared bridge and vlan are accepted" = !rejectedWith bridgeNeedle networkValid && !rejectedWith vlanNeedle networkValid;
    "that host evaluates" = networkValid.system.build.toplevel.drvPath != null;
    "the port is enslaved to the bridge" = networkValid.systemd.network.networks."10-lan-port".networkConfig.Bridge == "br-lan";
    "the trunk carries the vlan" = networkValid.systemd.network.networks."10-trunk".vlan == ["vlan100"];
    "an interface naming a missing bridge is rejected" = rejectedWith bridgeNeedle networkBadBridge;
    "the message names the interface and the bridge" = lib.hasInfix "lan-port (br-missing)" (messageOf bridgeNeedle networkBadBridge);
    "a missing bridge does not trip the vlan assertion" = !rejectedWith vlanNeedle networkBadBridge;
    "an interface naming a missing vlan is rejected" = rejectedWith vlanNeedle networkBadVlan;
    "the message names the missing vlan and not the declared one" = let
      message = messageOf vlanNeedle networkBadVlan;
    in
      lib.hasInfix "trunk (vlan200)" message && !lib.hasInfix "trunk (vlan100)" message;
    "a bridge and a vlan declared as raw netdevs are accepted" = !rejectedWith bridgeNeedle networkRawNetdevs && !rejectedWith vlanNeedle networkRawNetdevs;

    "the relocated host evaluates" = relocated.system.build.toplevel.drvPath != null;
    "the XDG directories follow the account's home" = userDirs.documents == "/srv/alice/Documents" && userDirs.download == "/srv/alice/Downloads";
    "the home directory Home Manager uses is the same one" = relocated.home-manager.users.alice.home.homeDirectory == "/srv/alice";
    "the persisted directories follow the account's home" = builtins.elem "/srv/alice/Documents" persistedDirs;
    "the persisted home is created under the persist root" = builtins.any (lib.hasPrefix "d /persist/srv/alice ") relocated.systemd.tmpfiles.rules;
    "the wipe script recreates the persisted home" = lib.hasInfix "mkdir -p /btrfs_tmp/persist/srv/alice" relocated.boot.initrd.systemd.services.root-wipe.script;

    "a lowercase user name is accepted" = (userNamed "alice").success && (userNamed "_svc-1").success;
    "a capitalised user name is refused" = !(userNamed "Alice").success;
    "a user name with a space is refused" = !(userNamed "alice smith").success;
    "a user name starting with a digit is refused" = !(userNamed "1alice").success;

    "a Claude Code theme from the list is accepted" = (themed "light-daltonized").success;
    "an unknown Claude Code theme is refused" = !(themed "solarized").success;
  }
