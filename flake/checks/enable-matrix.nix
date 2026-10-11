# flake/checks/enable-matrix.nix
# EXTENDED. The categorical enable-with-defaults matrix, where every
# `othrys.*.enable` option, set to true on an otherwise-default host,
# must either evaluate or fail the way the allowlist says. A module that
# legitimately requires configuration is listed in expectedFail with a
# fragment of the assertion it has to fail with, and MUST keep failing with
# it. An entry that evaluates means the allowlist is stale, and one that
# fails with another message means the module broke where its own
# assertion used to speak. Modules that fail without an assertion of their
# own sit in expectedFailUnnamed.
# Apps/desktop enables run on a workstation base (user + stylix +
# hyprland), and everything else runs headless. Every host of the matrix
# imports the four exports `default` leaves out, each beside the upstream
# module it writes into, so the walk finds othrys.system.stylix.enable,
# othrys.system.disko.enable and othrys.system.secrets.enable on the same
# option tree each host is built from, and othrys.system.impermanence.enable
# fails on its missing device alone. Hosts with none of the four are read
# by the fixtures in ./default.nix, ./theme-eval.nix and
# ./exports-optional-eval.nix. The fifth export, nixosModules.home, declares
# no option, so the walk does not need it. The workstation base carries it
# with the Home Manager module, and the headless hosts import neither, which
# is the shape a server has. Uncatchable errors (type errors like a null slipping
# into string interpolation) abort the whole check, the loudest possible
# failure, by design.
{
  pkgs,
  inputs,
  system,
  defaultModules,
  stylixModules,
  diskoModules,
  secretsModules,
  impermanenceModules,
  bootCore,
  bootBase,
  functioningHost,
}: let
  lib = inputs.nixpkgs.lib;

  mkSys = mods:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = defaultModules ++ [stylixModules diskoModules secretsModules impermanenceModules] ++ mods;
    };

  # Enumerate every othrys.*.enable option path from a minimal eval. An
  # option that mkRemovedOptionModule declares is still an option, declared
  # invisible and throwing when set, so it is not one to flip.
  collectEnables = prefix: opts:
    lib.concatLists (lib.mapAttrsToList (
        name: v: let
          path = prefix ++ [name];
        in
          if lib.isOption v
          then lib.optional (name == "enable" && (v.visible or true) != false) path
          else if builtins.isAttrs v
          then collectEnables path v
          else []
      )
      opts);

  enablePaths = collectEnables ["othrys"] (mkSys [bootCore]).options.othrys;

  headlessBase = [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
        # The matrix proves every module evaluates with its defaults, which is
        # a separate question from licensing policy. Some modules wrap unfree
        # packages (the NVIDIA driver is unfreeRedistributable), so both bases
        # opt in and a host decides for itself.
        allowUnfree = true;
      };
    }
  ];
  desktopBase = [
    functioningHost
    {
      othrys.system.stylix.enable = true;
      othrys.desktop.compositors.hyprland.enable = true;
      othrys.system.nix.allowUnfree = true;
    }
  ];

  isDesktopPath = p: builtins.elem (builtins.elemAt p 1) ["apps" "desktop"];

  # The enables above a nested one, such as othrys.services.ssh.enable above
  # othrys.services.ssh.server.enable. A nested enable sits under its parent's
  # mkIf, so flipping it with the parent off evaluates nothing of it. Each
  # parent is switched on with it, unless the parent is itself expected to
  # fail on its defaults. Those children are read by the module's own check,
  # where the parent is given what it requires.
  parentEnables = path:
    builtins.filter (p: builtins.elem p enablePaths && !isExpected (lib.concatStringsSep "." p))
    (lib.genList (n: lib.take (n + 2) path ++ ["enable"]) (lib.max 0 (builtins.length path - 3)));

  evalOf = path:
    mkSys ((
        if isDesktopPath path
        then desktopBase
        else headlessBase
      )
      ++ map (p: lib.setAttrByPath p true) ([path] ++ parentEnables path));

  evaluates = sys: (builtins.tryEval (sys.config.system.build.toplevel.drvPath != null)).success;

  # True when the host carries a failing assertion whose message holds
  # `fragment`. Each assertion is tried alone. A host missing a required
  # option often has another assertion that reads that option and throws, and
  # that one must not hide the assertion an entry names.
  failsWith = fragment: sys: let
    hit = a: let
      tried = builtins.tryEval (!a.assertion && lib.hasInfix fragment a.message);
    in
      tried.success && tried.value;
    found = builtins.tryEval (builtins.any hit sys.config.assertions);
  in
    found.success && found.value;

  # Modules whose bare `enable = true` is refused by an assertion of their
  # own, with a fragment of the message each has to fail with. An entry passes
  # only on that assertion, so a module that starts failing for another
  # reason is reported, and so is one that starts evaluating.
  expectedFail = {
    "othrys.apps.gaming.r2modman.enable" = "othrys.apps.gaming.r2modman requires othrys.apps.gaming.steam.enable";
    "othrys.apps.idea.enable" = "othrys.apps.idea: requires othrys.apps.languages.java.enable";
    "othrys.desktop.nightLight.enable" = "othrys.desktop.nightLight needs a location";
    "othrys.desktop.wallpaper.enable" = "othrys.desktop.wallpaper: no wallpaper is declared";
    # Its parent, the NVIDIA module, is on with it, so the bus ids are what
    # is missing.
    "othrys.hardware.nvidia.prime.enable" = "set intelBusId and nvidiaBusId";
    "othrys.apps.vscode.neovimIntegration.enable" = "neovimIntegration.enable requires othrys.apps.nixvim.enable";
    "othrys.services.containerization.docker.nvidia.enable" = "Docker NVIDIA support requires";
    "othrys.services.traefik.acme.enable" = "acme.enable requires acme.email and acme.dnsProvider";
    "othrys.services.alerting.enable" = "othrys.services.alerting: no datasource";
    "othrys.services.ddns.enable" = "othrys.services.ddns: set provider, hostnames, and credentialsFile";
    "othrys.services.grafana.enable" = "othrys.services.grafana: set secretKeyFile";
    # serverUrl has no default either. The MagicDNS assertion is the one that
    # reads nothing but options with defaults.
    "othrys.services.headscale.enable" = "requires baseDomain";
    "othrys.services.kea.enable" = "othrys.services.kea: dhcp4.interfaces must list at least one interface";
    "othrys.services.notify.enable" = "othrys.services.notify: set url";
    "othrys.system.autoUpgrade.enable" = "othrys.system.autoUpgrade: set exactly one upgrade source";
    # The disko layout is imported and off, so nothing names the device.
    "othrys.system.impermanence.enable" = "othrys.system.impermanence: set device";
    "othrys.system.nix.cachix.enable" = "othrys.system.nix.cachix: set name and publicKey";
    "othrys.system.users.enable" = "othrys.system.users: set passwordFile or initialHashedPassword";
  };

  # Modules whose bare `enable = true` fails some other way, where there is
  # no assertion of the module's own to name. Three declare an option with no
  # default, which the module system reports when the option is read, and the
  # bootloader collides with the GRUB the matrix base carries. Each is still
  # asserted to fail, by any catchable error.
  expectedFailUnnamed = [
    "othrys.hardware.ups.enable" # passwordFile has no default
    "othrys.services.router.enable" # wan.interface has no default
    "othrys.system.bootloader.enable" # conflicts with the matrix base's GRUB fixture
    "othrys.system.disko.enable" # device has no default
  ];

  results = map (path: let
    name = lib.concatStringsSep "." path;
    sys = evalOf path;
    pass = evaluates sys;
    named = builtins.hasAttr name expectedFail && failsWith expectedFail.${name} sys;
  in
    # Both fields are forced before the record is returned. A field left
    # as a thunk keeps its whole evaluated system reachable, and with one
    # system per enable option that is every system at once, which is more
    # memory than a CI runner or a workstation has.
    builtins.seq pass (builtins.seq named {inherit name pass named;}))
  enablePaths;

  isExpected = name: builtins.hasAttr name expectedFail || builtins.elem name expectedFailUnnamed;

  unexpected = builtins.filter (r: !r.pass && !isExpected r.name) results;
  stale = builtins.filter (r: r.pass && isExpected r.name) results;
  misnamed = builtins.filter (r: !r.pass && builtins.hasAttr r.name expectedFail && !r.named) results;
  unknown = builtins.filter (name: !(builtins.any (r: r.name == name) results)) (builtins.attrNames expectedFail ++ expectedFailUnnamed);

  report =
    lib.optionalString (unexpected != []) ''
      UNEXPECTED FAILURES (enable-with-defaults must eval, or be allowlisted with a clear othrys assertion):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}") unexpected}
    ''
    + lib.optionalString (stale != []) ''
      STALE ALLOWLIST (these now pass; remove them from expectedFail or expectedFailUnnamed):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}") stale}
    ''
    + lib.optionalString (misnamed != []) ''
      WRONG FAILURE (these fail, and no failing assertion holds the fragment expectedFail gives):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}, expected \"${expectedFail.${r.name}}\"") misnamed}
    ''
    + lib.optionalString (unknown != []) ''
      UNKNOWN ENTRIES (these name no othrys enable option):
      ${lib.concatMapStringsSep "\n" (name: "  - ${name}") unknown}
    '';
in
  pkgs.runCommand "othrys-enable-matrix" {
    inherit report;
    passAsFile = ["report"];
    total = toString (builtins.length results);
  } ''
    if [ -s "$reportPath" ]; then
      cat "$reportPath"
      exit 1
    fi
    echo "enable matrix: $total options green" > "$out"
  ''
