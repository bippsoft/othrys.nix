# flake/checks/impermanence-eval.nix
# CORE. What the impermanence module writes into the initrd, read back from an
# evaluated host. The wipe unit is a systemd stage-1 unit, and the scripted
# initrd drops it without an error, so a host that nothing else moved onto the
# systemd initrd kept its root forever. The device dependency is read back for
# a hyphenated LUKS name and for a plain device, since systemd escapes the
# path and a raw name never matches.
{
  hostConfig,
  mkExpectations,
  bootBase,
}: let
  host = extra:
    hostConfig [
      bootBase
      {
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
        othrys.system = {
          disko = {
            enable = true;
            device = "/dev/disk/by-id/example";
          };
          impermanence.enable = true;
        };
      }
      extra
    ];

  plain = host {};
  hyphenated = host {othrys.system.disko.luks.name = "crypt-root";};
  partition = host {othrys.system.impermanence.device = "/dev/disk/by-partlabel/root";};

  unitOf = cfg: cfg.boot.initrd.systemd.services.root-wipe;
  hasInfix = needle: s: builtins.match ".*${needle}.*" s != null;
in
  mkExpectations "othrys-eval-impermanence" {
    "impermanence turns the systemd initrd on" = plain.boot.initrd.systemd.enable;
    "the wipe unit is rendered into the initrd" = plain.boot.initrd.systemd.units ? "root-wipe.service";
    "findutils is on the stage-1 PATH" = builtins.any (p: p.pname or "" == "findutils") plain.boot.initrd.systemd.initrdBin;
    "the unit requires the LUKS mapping by default" = (unitOf plain).requires == ["dev-mapper-cryptroot.device"];
    "a hyphenated LUKS name is escaped in the unit name" = (unitOf hyphenated).requires == ["dev-mapper-crypt\\x2droot.device"];
    "a plain device becomes its own device unit" = (unitOf partition).requires == ["dev-disk-by\\x2dpartlabel-root.device"];
    "the unit runs after the resume from hibernation" = builtins.elem "systemd-hibernate-resume.service" (unitOf plain).after;
    "the unit runs before the root is mounted" = (unitOf plain).before == ["sysroot.mount"];
    "the script mounts the top-level subvolume" = hasInfix "subvolid=5" (unitOf plain).script;
    "the script mounts the device the option names" = hasInfix "/dev/disk/by-partlabel/root" (unitOf partition).script;
    "the script does not call find" = let
      lines = builtins.filter builtins.isString (builtins.split "\n" (unitOf plain).script);
      code = builtins.filter (l: builtins.match "[[:space:]]*#.*" l == null) lines;
    in
      !builtins.any (hasInfix "find ") code;
    "the new root is created before the prune" = let
      s = (unitOf plain).script;
      at = needle: builtins.stringLength (builtins.head (builtins.split needle s));
    in
      at "btrfs subvolume create /btrfs_tmp/root" < at "shopt -s nullglob";
  }
