# flake/checks/enable-matrix.nix
# EXTENDED. The categorical enable-with-defaults matrix, where every
# `othrys.*.enable` option, set to true on an otherwise-default host,
# must either evaluate or fail via a caught assertion/throw. Modules
# that legitimately require configuration are listed in expectedFail,
# and MUST keep failing (a passing entry means the allowlist is stale).
# Apps/desktop enables run on a workstation base (user + stylix +
# hyprland), and everything else runs headless. Uncatchable errors (type
# errors like a null slipping into string interpolation) abort the
# whole check, the loudest possible failure, by design.
{
  pkgs,
  inputs,
  system,
  upstreamModules,
  bootCore,
  bootBase,
  functioningHost,
}: let
  lib = inputs.nixpkgs.lib;

  mkSys = mods:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules = upstreamModules ++ mods;
    };

  # Enumerate every othrys.*.enable option path from a minimal eval.
  collectEnables = prefix: opts:
    lib.concatLists (lib.mapAttrsToList (
        name: v: let
          path = prefix ++ [name];
        in
          if lib.isOption v
          then lib.optional (name == "enable") path
          else if builtins.isAttrs v
          then collectEnables path v
          else []
      )
      opts);

  enablePaths = collectEnables ["othrys"] (mkSys [bootCore]).options.othrys;

  headlessBase = [
    bootBase
    {othrys.system.nix.enable = true;}
  ];
  desktopBase = [
    functioningHost
    {
      othrys.system.stylix.enable = true;
      othrys.desktop.compositors.hyprland.enable = true;
    }
  ];

  isDesktopPath = p: builtins.elem (builtins.elemAt p 1) ["apps" "desktop"];

  evalPath = path:
    (builtins.tryEval (
      (mkSys ((
          if isDesktopPath path
          then desktopBase
          else headlessBase
        )
        ++ [(lib.setAttrByPath path true)]))
      .config
      .system
      .build
      .toplevel
      .drvPath
      != null
    ))
    .success;

  # Modules whose bare `enable = true` intentionally fails with an
  # assertion or a required-option error. Each entry is ALSO asserted
  # to fail. If one starts passing, remove it here.
  expectedFail = [
    "othrys.apps.ai.mcp.github.enable" # requires othrys.system.secrets
    "othrys.apps.gaming.r2modman.enable" # requires gaming.steam
    "othrys.services.headscale.enable" # requires serverUrl + MagicDNS domain/nameservers
    "othrys.services.kea.enable" # requires dhcp4.interfaces
    "othrys.services.router.enable" # requires wan.interface
    "othrys.system.bootloader.enable" # conflicts with the matrix base's GRUB fixture
    "othrys.system.disko.enable" # requires device
    "othrys.system.impermanence.enable" # requires disko
    "othrys.system.users.enable" # requires initialPassword or passwordFile
    "othrys.services.notify.enable" # requires url (or a local ntfy server)
    "othrys.services.alerting.enable" # requires a datasource (VM or monitoring)
    "othrys.services.grafana.enable" # requires secretKeyFile
    "othrys.hardware.ups.enable" # requires passwordFile
    "othrys.system.autoUpgrade.enable" # requires the fleet flake URI
    "othrys.services.ddns.enable" # requires provider/hostnames/credentialsFile
    "othrys.apps.idea.enable" # requires othrys.apps.languages.java
    "othrys.services.scrutiny.collector.enable" # collector-only host requires collector.endpoint
  ];

  results =
    map (path: {
      name = lib.concatStringsSep "." path;
      pass = evalPath path;
    })
    enablePaths;

  unexpected = builtins.filter (r: !r.pass && !(builtins.elem r.name expectedFail)) results;
  stale = builtins.filter (r: r.pass && builtins.elem r.name expectedFail) results;

  report =
    lib.optionalString (unexpected != []) ''
      UNEXPECTED FAILURES (enable-with-defaults must eval, or be allowlisted with a clear othrys assertion):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}") unexpected}
    ''
    + lib.optionalString (stale != []) ''
      STALE ALLOWLIST (these now pass; remove them from expectedFail):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}") stale}
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
