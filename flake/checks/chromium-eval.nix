# flake/checks/chromium-eval.nix
# CORE. Chromium packages, local extension manifests, registry guards and typed refusals
{
  lib,
  pkgs,
  hostConfig,
  mkExpectations,
  rejectedWith,
  functioningHost,
  bootBase,
  bootCore,
  homeModules,
  accountNoHomeManager,
}: let
  host = extra: hostConfig [functioningHost extra];
  enabled = {othrys.apps.chromium.enable = true;};
  plain = host enabled;
  disabled = host {};
  unmanaged = hostConfig [bootBase homeModules enabled];
  anonymous = hostConfig [bootCore enabled];
  noHM = hostConfig [accountNoHomeManager enabled];
  home = cfg: cfg.home-manager.users.alice;
  chromium = cfg: (home cfg).programs.chromium;
  installs = cfg: package: builtins.any (p: p.drvPath == package.drvPath) (home cfg).home.packages;
  onSystemPath = cfg: package: builtins.any (p: p.drvPath == package.drvPath) cfg.environment.systemPackages;
  registry = cfg: cfg.othrys.internal.homeConfig."apps.chromium".programs.chromium;
  extensions = cfg: (chromium cfg).extensions;
  ids = cfg: map (e: e.id) (extensions cfg);
  manifestFiles = cfg: lib.filterAttrs (name: _: lib.hasInfix "/chromium/External Extensions/" name) (home cfg).home.file;
  # fromJSON requires context-free text. These comparisons inspect paths without
  # building the CRXs whose context Home Manager preserved in the JSON.
  manifest = cfg: id:
    builtins.fromJSON (builtins.unsafeDiscardStringContext
      (home cfg).home.file."/home/alice/.config/chromium/External Extensions/${id}.json".text);

  customId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  custom = {
    url = "https://example.com/extensions/example-1.2.3.4.crx";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    version = "1.2.3.4";
  };
  declared = host {
    imports = [enabled];
    othrys.apps.chromium.extensions.${customId} = custom;
  };
  overridden = host {
    imports = [enabled];
    othrys.apps.chromium.package = pkgs.chromium;
  };

  # An overridable package records the argument Home Manager gives its wrapper,
  # without depending on the browser derivation's internal build attributes.
  probe = lib.makeOverridable ({commandLineArgs ? ""}:
    pkgs.runCommand "chromium-check-browser" {
      inherit commandLineArgs;
      passthru.receivedArgs = commandLineArgs;
    } "mkdir -p $out") {};
  withArgs = host {
    imports = [enabled];
    othrys.apps.chromium = {
      package = probe;
      commandLineArgs = ["--ozone-platform=wayland" "--enable-logging=stderr"];
    };
  };

  invalidId = id:
    hostConfig [
      bootCore
      {
        othrys.apps.chromium = {
          enable = true;
          extensions.${id} = custom;
        };
      }
    ];

  # Read only the typed leaves under tryEval. A submodule's required fields
  # are lazy, so trying the enclosing attrset alone would accept missing ones.
  attempted = value:
    builtins.tryEval (let
      cfg = hostConfig [bootCore {othrys.apps.chromium.extensions.${customId} = value;}];
      entry = cfg.othrys.apps.chromium.extensions.${customId};
      leaves = map (field: entry.${field}) ["url" "hash" "version"];
    in
      builtins.deepSeq leaves true);
  refused = value: !(attempted value).success;
  versionRefusals = lib.listToAttrs (map (version:
    lib.nameValuePair "extension version '${version}' is refused" (refused (custom // {inherit version;}))) [
    ""
    "1.2.3.4.5"
    "1..2"
    "v1.2"
    "1.2-beta"
    "-1"
    "1.2.3.65536"
    "65536"
    "0"
    "0.0"
    "0.0.0"
    "0.0.0.0"
    "01.2"
    "1.00"
  ]);
  acceptedVersions = ["1" "0.1" "1.2.3" "1.2.3.4" "65535.0.65535.0"];
  emptyBrowser = builtins.tryEval (hostConfig [bootCore {othrys.desktop.defaultBrowser = "";}]).othrys.desktop.defaultBrowser;
in
  mkExpectations "othrys-eval-chromium" (versionRefusals
    // {
      "Chromium is disabled by default" = !disabled.othrys.apps.chromium.enable && !(chromium disabled).enable;
      "the disabled module writes neither registry entry" = !(disabled.othrys.internal.homeConfig ? "apps.chromium") && !(disabled.othrys.internal.persist ? "apps.chromium");
      "the disabled module writes no external extension manifest" = manifestFiles disabled == {};
      "the disabled module installs no Ungoogled Chromium package" = !installs disabled pkgs.ungoogled-chromium && !onSystemPath disabled pkgs.ungoogled-chromium;
      "a bare enable reaches Home Manager" = (chromium plain).enable && (registry plain).enable;
      "the enabled managed host evaluates" = plain.system.build.toplevel.drvPath != null;
      "the default package is Ungoogled Chromium" = (chromium plain).package.drvPath == pkgs.ungoogled-chromium.drvPath;
      "the browser is installed for the user only" = installs plain (chromium plain).finalPackage && !onSystemPath plain (chromium plain).finalPackage;
      "the default launch arguments are empty" = (chromium plain).commandLineArgs == [];
      "without launch arguments the package is not customized" = (chromium plain).finalPackage.drvPath == (chromium plain).package.drvPath;
      "a package override reaches Home Manager and the user PATH" = (chromium overridden).package.drvPath == pkgs.chromium.drvPath && installs overridden pkgs.chromium && !onSystemPath overridden pkgs.chromium;
      "launch arguments pass through unchanged and in order" = (chromium withArgs).commandLineArgs == ["--ozone-platform=wayland" "--enable-logging=stderr"];
      "Home Manager customizes the wrapper with the launch arguments" = (chromium withArgs).finalPackage.receivedArgs == "--ozone-platform=wayland --enable-logging=stderr";
      "the customized wrapper is installed instead of the original package" = installs withArgs (chromium withArgs).finalPackage && !installs withArgs probe;

      "no extension is declared by default" = plain.othrys.apps.chromium.extensions == {} && extensions plain == [] && manifestFiles plain == {};
      "a declared extension is fetched from its URL and hash" = lib.all (e: e.crxPath.url == custom.url && e.crxPath.outputHash == custom.hash) (registry declared).extensions;
      "a declared extension writes one local manifest with its version" =
        ids declared
        == [customId]
        && builtins.attrNames (manifestFiles declared) != []
        && builtins.length (builtins.attrNames (manifestFiles declared)) == 1
        && (manifest declared customId).external_version == "1.2.3.4"
        && builtins.attrNames (manifest declared customId) == ["external_crx" "external_version"]
        && lib.hasPrefix "/nix/store/" (manifest declared customId).external_crx;
      "the profile is registered for persistence at mode 0700" =
        plain.othrys.internal.persist."apps.chromium".user.directories
        == [
          {
            directory = ".config/chromium";
            mode = "0700";
          }
        ];

      "an unmanaged host materializes no Home Manager user" = unmanaged.home-manager.users == {} && !unmanaged.othrys.system.users.homeManaged;
      "the unmanaged host evaluates with Chromium enabled" = unmanaged.system.build.toplevel.drvPath != null;
      "an unmanaged host keeps the contribution in the registry" = (registry unmanaged).enable && !onSystemPath unmanaged pkgs.ungoogled-chromium;
      "an anonymous default-only host evaluates without reading a user name" = anonymous.system.build.toplevel.drvPath != null;
      "an anonymous default-only host writes no optional upstream namespace" = !(anonymous ? home-manager) && !(anonymous ? stylix) && !(anonymous ? disko) && !(anonymous ? sops) && !(anonymous.environment ? persistence);
      "an anonymous host creates no primary account or system browser" = !(anonymous.users.users ? alice) && !onSystemPath anonymous pkgs.ungoogled-chromium;
      "an account without Home Manager evaluates with Chromium enabled" = noHM.system.build.toplevel.drvPath != null && !(noHM ? home-manager) && !noHM.othrys.system.users.homeManaged;
      "an account without Home Manager installs no system browser" = !onSystemPath noHM pkgs.ungoogled-chromium;

      "a short extension ID is rejected with the othrys option name" = rejectedWith "othrys.apps.chromium.extensions" (invalidId "abc");
      "an uppercase extension ID is rejected with the othrys option name" = rejectedWith "othrys.apps.chromium.extensions" (invalidId "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
      "an ID outside a through p is rejected with the othrys option name" = rejectedWith "othrys.apps.chromium.extensions" (invalidId "qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq");
      "a long extension ID is rejected with the othrys option name" = rejectedWith "othrys.apps.chromium.extensions" (invalidId "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
      "a valid extension ID is accepted" = !rejectedWith "othrys.apps.chromium.extensions" declared;
      "an HTTP extension URL is refused" = refused (custom // {url = "http://example.com/example.crx";});
      "an empty HTTPS URL is refused" = refused (custom // {url = "https://";});
      "a non-SRI hash is refused" = refused (custom // {hash = "0000000000000000000000000000000000000000000000000000000000000000";});
      "an SRI hash with another algorithm is refused" = refused (custom // {hash = "sha512-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";});
      "a truncated SHA256 SRI hash is refused" = refused (custom // {hash = "sha256-AAAA=";});
      "a missing download URL is refused" = refused (builtins.removeAttrs custom ["url"]);
      "a missing hash is refused" = refused (builtins.removeAttrs custom ["hash"]);
      "a missing version is refused" = refused (builtins.removeAttrs custom ["version"]);
      "one through four version components and the 65535 boundary are accepted" = lib.all (version: (attempted (custom // {inherit version;})).success) acceptedVersions;
      "an empty shared defaultBrowser is refused by its type" = !emptyBrowser.success;
    })
