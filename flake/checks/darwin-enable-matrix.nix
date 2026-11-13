# flake/checks/darwin-enable-matrix.nix
# EXTENDED. The enable-with-defaults matrix of ./enable-matrix.nix on a
# nix-darwin host. Every `othrys.*.enable` option that the darwin exports
# declare is set to true on its own, over a managed account with Home
# Manager for the apps and desktop options and over a host with no account
# for every other one, as enable-matrix splits its bases, with the Home
# Manager, Stylix and secrets adapters imported beside their upstream
# modules. The host must evaluate or fail the way the allowlist says. An entry that evaluates is a stale allowlist, and one
# that fails with another message means the module broke where its own
# assertion used to speak. The darwin toplevel is evaluated and not built,
# so the check runs on any system, and CI runs it on a Mac beside the
# darwin builds.
{
  pkgs,
  inputs,
  darwinEval,
  darwinBase,
  darwinHomeModules,
  darwinManagedBase,
  darwinStylixModules,
  darwinSecretsModules,
}: let
  inherit (inputs.nixpkgs) lib;

  adapters = [
    darwinBase
    darwinHomeModules
    darwinStylixModules
    darwinSecretsModules
    # Licensing is a separate question from whether a module evaluates, so
    # both bases opt in, as enable-matrix does.
    {othrys.system.nix.allowUnfree = true;}
  ];
  # A host with Nix managed and no account, where a module that writes for
  # the user has to stay quiet.
  headlessBase =
    adapters
    ++ [
      {
        othrys.system.nix = {
          enable = true;
          stateVersion = "26.05";
        };
      }
    ];
  managedBase = adapters ++ [darwinManagedBase];
  mkSys = mods: darwinEval (headlessBase ++ mods);

  isDesktopPath = p: builtins.elem (builtins.elemAt p 1) ["apps" "desktop"];

  # Every othrys.*.enable option path the darwin tree declares. An option
  # that mkRemovedOptionModule declares is invisible and throws when set, so
  # it is not one to flip.
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
  enablePaths = collectEnables ["othrys"] (mkSys []).options.othrys;

  # A nested enable sits under its parent's mkIf, so each parent is switched
  # on with it, unless the parent is itself expected to fail on its defaults.
  parentEnables = path:
    builtins.filter (p: builtins.elem p enablePaths && !isExpected (lib.concatStringsSep "." p))
    (lib.genList (n: lib.take (n + 2) path ++ ["enable"]) (lib.max 0 (builtins.length path - 3)));

  evalOf = path:
    darwinEval ((
        if isDesktopPath path
        then managedBase
        else headlessBase
      )
      ++ map (p: lib.setAttrByPath p true) ([path] ++ parentEnables path));
  evaluates = sys: (builtins.tryEval (sys.config.system.build.toplevel.drvPath != null)).success;

  # True when the host carries a failing assertion whose message holds
  # `fragment`, each assertion tried alone, as in enable-matrix.
  failsWith = fragment: sys: let
    hit = a: let
      tried = builtins.tryEval (!a.assertion && lib.hasInfix fragment a.message);
    in
      tried.success && tried.value;
    found = builtins.tryEval (builtins.any hit sys.config.assertions);
  in
    found.success && found.value;

  # Modules whose bare `enable = true` on darwin is refused by an assertion
  # of their own, with a fragment of the message each has to fail with.
  expectedFail = {
    # No agent is on either, and that assertion fails beside this one.
    "othrys.apps.ai.t3code.enable" = "othrys.apps.ai.t3code.mode is unset";
    # Its nested enables are walked with it off, since it is listed here,
    # and so they evaluate.
    "othrys.apps.ai.paseo.enable" = "neither othrys.apps.ai.codex.enable nor othrys.apps.ai.claude-code.enable is set";
    "othrys.apps.idea.enable" = "othrys.apps.idea: requires othrys.apps.languages.java.enable";
    "othrys.apps.vscode.neovimIntegration.enable" = "neovimIntegration.enable requires othrys.apps.nixvim.enable";
    "othrys.system.nix.cachix.enable" = "othrys.system.nix.cachix: set name and publicKey";
    # nix-darwin has no ssh host key to decrypt with.
    "othrys.system.secrets.enable" = "sops-nix has no key to decrypt with";
  };

  results = map (path: let
    name = lib.concatStringsSep "." path;
    sys = evalOf path;
    pass = evaluates sys;
    named = builtins.hasAttr name expectedFail && failsWith expectedFail.${name} sys;
  in
    # Both fields are forced before the record is returned, so no evaluated
    # system stays reachable from the list.
    builtins.seq pass (builtins.seq named {inherit name pass named;}))
  enablePaths;

  isExpected = name: builtins.hasAttr name expectedFail;

  unexpected = builtins.filter (r: !r.pass && !isExpected r.name) results;
  stale = builtins.filter (r: r.pass && isExpected r.name) results;
  misnamed = builtins.filter (r: !r.pass && isExpected r.name && !r.named) results;
  unknown = builtins.filter (name: !(builtins.any (r: r.name == name) results)) (builtins.attrNames expectedFail);

  report =
    lib.optionalString (unexpected != []) ''
      UNEXPECTED FAILURES (enable-with-defaults must eval on darwin, or be allowlisted with a clear othrys assertion):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}") unexpected}
    ''
    + lib.optionalString (stale != []) ''
      STALE ALLOWLIST (these now pass; remove them from expectedFail):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}") stale}
    ''
    + lib.optionalString (misnamed != []) ''
      WRONG FAILURE (these fail, and no failing assertion holds the fragment expectedFail gives):
      ${lib.concatMapStringsSep "\n" (r: "  - ${r.name}, expected \"${expectedFail.${r.name}}\"") misnamed}
    ''
    + lib.optionalString (unknown != []) ''
      UNKNOWN ENTRIES (these name no othrys enable option on darwin):
      ${lib.concatMapStringsSep "\n" (name: "  - ${name}") unknown}
    '';
in
  pkgs.runCommand "othrys-darwin-enable-matrix" {
    inherit report;
    passAsFile = ["report"];
    total = toString (builtins.length results);
  } ''
    if [ -s "$reportPath" ]; then
      cat "$reportPath"
      exit 1
    fi
    echo "darwin enable matrix: $total options green" > "$out"
  ''
