# flake/checks/bootloader.nix
# CORE. Every othrys.system.bootloader.type with secureBoot off and on. The
# combinations that work must evaluate and set the loader options they claim
# to, and the ones that cannot work must fail on their own named assertion.
# Evaluation only. Nothing here boots under firmware Secure Boot.
{
  pkgs,
  inputs,
  system,
  upstreamModules,
  bootCore,
}: let
  lib = inputs.nixpkgs.lib;

  # bootCore's GRUB fixture conflicts with a module that owns the bootloader,
  # so the managed types take its root filesystem alone. "none" keeps the
  # whole fixture, which is the shape that type exists for, a loader the host
  # configures by hand.
  rootOnly = {inherit (bootCore) fileSystems;};

  # upstreamModules stays as every other fixture has it, without lanzaboote.
  # The one case that needs the module passes it through extraModules, so the
  # rest keep proving that a consumer who never imports it evaluates.
  mkConfig = {
    type,
    secureBoot,
    extraModules ? [],
  }:
    (lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs;};
      modules =
        upstreamModules
        ++ extraModules
        ++ [
          (
            if type == "none"
            then bootCore
            else rootOnly
          )
          {
            system.stateVersion = "26.05";
            othrys.system.bootloader = {
              enable = true;
              inherit type secureBoot;
            };
          }
        ];
    })
    .config;

  failedAssertions = config:
    map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions);

  hasSbctl = config: lib.any (p: lib.getName p == "sbctl") config.environment.systemPackages;

  # A case that must evaluate. `expect` maps a label to the value read back
  # from the evaluated config and the value it must equal. The toplevel is
  # forced only once the assertions are known to pass, so a failure names the
  # assertion instead of aborting the whole check.
  accepts = name: args: expect: let
    config = mkConfig args;
    failed = failedAssertions config;
    wrong = lib.filterAttrs (_: v: v.actual != v.expected) (expect config);
  in
    if failed != []
    then ["${name}: must evaluate, but these assertions failed: ${lib.concatStringsSep " | " failed}"]
    else
      builtins.seq config.system.build.toplevel.drvPath
      (lib.mapAttrsToList (
          label: v: "${name}: ${label} is ${builtins.toJSON v.actual}, expected ${builtins.toJSON v.expected}"
        )
        wrong);

  # A case that must be rejected, by exactly one assertion whose message
  # contains `needle`. Reading config.assertions instead of catching a throw
  # from the toplevel is what ties the failure to the assertion under test,
  # since any other evaluation error would satisfy a tryEval just as well.
  rejects = name: args: needle: let
    failed = failedAssertions (mkConfig args);
  in
    lib.optional (!(builtins.length failed == 1 && lib.hasInfix needle (builtins.head failed)))
    "${name}: only the assertion containing '${needle}' may fail, got: ${builtins.toJSON failed}";

  problems = lib.concatLists [
    (accepts "limine" {
        type = "limine";
        secureBoot = false;
      } (c: {
        "boot.loader.limine.enable" = {
          actual = c.boot.loader.limine.enable;
          expected = true;
        };
        "boot.loader.limine.secureBoot.enable" = {
          actual = c.boot.loader.limine.secureBoot.enable;
          expected = false;
        };
        "sbctl in environment.systemPackages" = {
          actual = hasSbctl c;
          expected = false;
        };
      }))

    (accepts "systemd-boot" {
        type = "systemd-boot";
        secureBoot = false;
      } (c: {
        "boot.loader.systemd-boot.enable" = {
          actual = c.boot.loader.systemd-boot.enable;
          expected = true;
        };
      }))

    (accepts "grub" {
        type = "grub";
        secureBoot = false;
      } (c: {
        "boot.loader.grub.enable" = {
          actual = c.boot.loader.grub.enable;
          expected = true;
        };
      }))

    (accepts "none" {
        type = "none";
        secureBoot = false;
      } (c: {
        "boot.loader.limine.enable" = {
          actual = c.boot.loader.limine.enable;
          expected = false;
        };
        "boot.loader.systemd-boot.enable" = {
          actual = c.boot.loader.systemd-boot.enable;
          expected = false;
        };
      }))

    (accepts "limine with secureBoot" {
        type = "limine";
        secureBoot = true;
      } (c: {
        "boot.loader.limine.secureBoot.enable" = {
          actual = c.boot.loader.limine.secureBoot.enable;
          expected = true;
        };
        "sbctl in environment.systemPackages" = {
          actual = hasSbctl c;
          expected = true;
        };
      }))

    (accepts "systemd-boot with secureBoot and lanzaboote" {
        type = "systemd-boot";
        secureBoot = true;
        extraModules = [inputs.lanzaboote.nixosModules.lanzaboote];
      } (c: {
        "boot.lanzaboote.enable" = {
          actual = c.boot.lanzaboote.enable;
          expected = true;
        };
        "boot.lanzaboote.pkiBundle" = {
          actual = c.boot.lanzaboote.pkiBundle;
          expected = "/var/lib/sbctl";
        };
        "boot.loader.systemd-boot.enable" = {
          actual = c.boot.loader.systemd-boot.enable;
          expected = false;
        };
        "sbctl in environment.systemPackages" = {
          actual = hasSbctl c;
          expected = true;
        };
      }))

    (rejects "systemd-boot with secureBoot, lanzaboote not imported" {
      type = "systemd-boot";
      secureBoot = true;
    } "import lanzaboote.nixosModules.lanzaboote")

    (rejects "grub with secureBoot" {
      type = "grub";
      secureBoot = true;
    } "GRUB has no Secure Boot support")

    (rejects "none with secureBoot" {
      type = "none";
      secureBoot = true;
    } "manages no bootloader")
  ];

  report = lib.concatMapStringsSep "\n" (p: "  - ${p}") problems;
in
  pkgs.runCommand "othrys-eval-bootloader" {
    inherit report;
    passAsFile = ["report"];
  } ''
    if [ -s "$reportPath" ]; then
      echo "BOOTLOADER CASES FAILING:"
      cat "$reportPath"
      exit 1
    fi
    echo "bootloader: every type evaluates with secureBoot off and on as declared" > "$out"
  ''
