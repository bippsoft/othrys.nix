# flake/checks/senpai-eval.nix
# CORE. What the senpai module hands Home Manager and the persistence
# registry on NixOS, read back from evaluated hosts. The address, the
# nickname, the password command and the soju default are strings a host
# evaluates cleanly with whether or not they are right, and so is the
# senpai.scfg Home Manager renders from them, which is read as the text of
# its home.file entry and needs no build. Every refusal is matched by a
# fragment of its message. The darwin half sits in ./darwin-eval.nix, since
# nixosSystem cannot evaluate on a Mac.
{
  lib,
  hostConfig,
  impermanenceModules,
  mkExpectations,
  rejectedWith,
  functioningHost,
  inputs,
  system,
}: let
  coreutils = inputs.nixpkgs.legacyPackages.${system}.coreutils;
  host = modules: hostConfig ([functioningHost] ++ modules);
  senpaiWith = settings: {othrys.apps.senpai = {enable = true;} // settings;};
  direct = {
    address = "irc.example.com:6697";
    nickname = "alice";
  };
  passwordFile = "/run/secrets/senpai-password";

  off = host [];
  plain = host [(senpaiWith direct)];
  withFile = host [(senpaiWith (direct // {inherit passwordFile;}))];
  withSettings = host [
    (senpaiWith (direct
      // {
        settings = {
          username = "alice";
          channel = ["#example"];
        };
      }))
  ];

  # soju on the same host, with no address given.
  sojuDefault = host [{othrys.services.soju.enable = true;} (senpaiWith {nickname = "alice";})];
  soju6680 = host [
    {
      othrys.services.soju = {
        enable = true;
        port = 6680;
      };
    }
    (senpaiWith {nickname = "alice";})
  ];
  sojuExplicit = host [{othrys.services.soju.enable = true;} (senpaiWith direct)];

  # Refusals.
  noAddress = host [(senpaiWith {nickname = "alice";})];
  noNickname = host [(senpaiWith {address = "irc.example.com:6697";})];
  withPassword = host [(senpaiWith (direct // {settings.password = "x";}))];
  withPasswordCmd = host [(senpaiWith (direct // {settings.password-cmd = ["true"];}))];
  # The type refuses a store path, which throws on reading the option
  # rather than failing an assertion.
  storePath = host [(senpaiWith (direct // {passwordFile = "${builtins.storeDir}/x";}))];

  # No disk layout is imported, so the wipe is given its device by hand and
  # the two volumes impermanence marks as needed for boot are named.
  impermanent = {
    imports = [impermanenceModules];
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
  wiped = host [impermanent (senpaiWith direct)];
  wipedOff = host [impermanent];
  # environment.persistence holds no user entry at all on a host where no
  # module persists a home path, hence the fallbacks.
  userDirsOf = cfg: cfg.environment.persistence.${cfg.othrys.system.impermanence.persistRoot}.users.alice.directories or [];
  persistsUser = path: cfg: builtins.any (entry: (entry.dirPath or entry.directory) == path) (userDirsOf cfg);

  hm = h: h.home-manager.users.alice;
  senpai = h: (hm h).programs.senpai;
  conf = h: (senpai h).config;
  # Home Manager writes the file under xdg.configHome on Linux, through
  # home.file and not xdg.configFile.
  lines = h: lib.splitString "\n" ((hm h).home.file."/home/alice/.config/senpai/senpai.scfg".text or "");
  hasLine = line: h: builtins.elem line (lines h);
  hasPasswordLine = h: builtins.any (l: lib.hasPrefix "password " l || l == "password") (lines h);
  hasPasswordCmdLine = h: builtins.any (lib.hasPrefix "password-cmd") (lines h);
  accepted = h: !rejectedWith "othrys.apps.senpai" h;
in
  mkExpectations "othrys-eval-senpai" {
    # Absent case.
    "with the module off nothing reaches the registry" = !(off.othrys.internal.homeConfig ? "apps.senpai") && !(off.othrys.internal.persist ? "apps.senpai");
    "with the module off Home Manager runs no senpai" = !(senpai off).enable;
    "with the module off nothing is persisted for senpai" = !(persistsUser "/home/alice/.cache/senpai" wipedOff);

    # A server named directly.
    "a host with an address and a nickname trips no senpai assertion" = accepted plain;
    "the user's senpai is enabled" = (senpai plain).enable;
    "the config holds the address, the nickname and no password" =
      conf plain
      == {
        address = "irc.example.com:6697";
        nickname = "alice";
        password = null;
        password-cmd = null;
      };
    "senpai.scfg names the address and the nickname" = hasLine "address irc.example.com:6697" plain && hasLine "nickname alice" plain;
    "senpai.scfg carries no password line without a password file" = !(hasPasswordLine plain) && !(hasPasswordCmdLine plain);

    # The password file.
    "a password file trips no senpai assertion" = accepted withFile;
    "a password file is read by coreutils' cat from the store" = (conf withFile).password-cmd == ["${coreutils}/bin/cat" passwordFile];
    "a password file sets no password" = (conf withFile).password == null;
    "senpai.scfg runs cat on the password file and holds no password" =
      hasLine "password-cmd ${coreutils}/bin/cat ${passwordFile}" withFile
      && !(hasPasswordLine withFile);

    # Further directives.
    "settings reach the config beside the address and the nickname" =
      (conf withSettings).username
      == "alice"
      && (conf withSettings).channel == ["#example"]
      && (conf withSettings).address == "irc.example.com:6697"
      && (conf withSettings).nickname == "alice";
    "senpai.scfg names the settings' directives" = hasLine "username alice" withSettings && hasLine "channel #example" withSettings;

    # soju on the same host.
    "with soju on and no address senpai connects to soju's loopback listener" =
      accepted sojuDefault
      && (conf sojuDefault).address == "irc+insecure://127.0.0.1:6667";
    "the soju default follows soju's port" = (conf soju6680).address == "irc+insecure://127.0.0.1:6680";
    "an address given beside soju wins over the soju default" = (conf sojuExplicit).address == "irc.example.com:6697";

    # Persistence.
    "senpai's cache directory is persisted under the user" = persistsUser "/home/alice/.cache/senpai" wiped;
    "senpai's config directory is not persisted" = !(persistsUser "/home/alice/.config/senpai" wiped);

    # Refusals.
    "an unset address with soju off is refused" = rejectedWith "othrys.apps.senpai: address is unset" noAddress;
    "an unset nickname is refused" = rejectedWith "othrys.apps.senpai: nickname is unset" noNickname;
    "settings.password is refused" = rejectedWith "settings.password and settings.password-cmd are refused" withPassword;
    "settings.password-cmd is refused" = rejectedWith "settings.password and settings.password-cmd are refused" withPasswordCmd;
    "a store path for passwordFile is refused by its type" =
      !(builtins.tryEval storePath.othrys.apps.senpai.passwordFile).success
      && (builtins.tryEval withFile.othrys.apps.senpai.passwordFile).success;

    # A missing value leaves Home Manager alone.
    "an unset nickname writes nothing to Home Manager" = !(noNickname.othrys.internal.homeConfig ? "apps.senpai") && !(senpai noNickname).enable;
    "an unset address writes nothing to Home Manager" = !(noAddress.othrys.internal.homeConfig ? "apps.senpai") && !(senpai noAddress).enable;
  }
