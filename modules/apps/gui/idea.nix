# modules/apps/gui/idea.nix
# IntelliJ IDEA - JetBrains JVM IDE
#
# Plugins follow the languages-module shape, a curated table here and a boolean
# per entry for consumers. A host says `plugins.ideavim = true` and never sees
# a marketplace URL or a hash, the same way it says `languages.rust.enable`
# and never sees a package set.
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.idea;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # Curated plugin catalogue. Every entry pins one marketplace release.
  #
  # The url carries the plugin id and the update id, so it pins exactly. To
  # bump one, query the marketplace for the current update against the IDE
  # build:
  #
  #   curl -s 'https://plugins.jetbrains.com/api/search/plugins?search=<name>&build=<IU-build>&max=1'
  #   curl -s 'https://plugins.jetbrains.com/api/plugins/<id>/updates?size=5'
  #   nix-prefetch-url --unpack --type sha256 <url>
  #
  # `build` comes from `<ide>/build.txt`. Filtering the search by it is what
  # keeps the catalogue compatible, since addPlugins does no compatibility check and
  # a plugin built for an older IDEA installs happily and is then refused at
  # startup.
  pluginCatalog = {
    nixidea = {
      name = "NixIDEA";
      description = "Nix language support: highlighting, navigation, completion.";
      version = "0.4.0.22";
      url = "https://plugins.jetbrains.com/files/8607/1098881/NixIDEA-0.4.0.22.zip";
      hash = "sha256-0vzh9uUWfaP42z7WkySHbr8LDwDPCsf2l4Lhdg+kwNE=";
    };
    ideavim = {
      name = "IdeaVim";
      description = "Vim emulation.";
      version = "2.46.2";
      url = "https://plugins.jetbrains.com/files/164/1149038/IdeaVIM-2.46.2.zip";
      hash = "sha256-cP/Hjd+cTim55zNiWD5byyDE1EU4hI/47lp7VpugJtc=";
    };
    key-promoter-x = {
      name = "Key Promoter X";
      description = "Shows the keyboard shortcut for whatever was just clicked.";
      version = "2026.1.2";
      url = "https://plugins.jetbrains.com/files/9792/1098878/Key_Promoter_X-2026.1.2.zip";
      hash = "sha256-l/sWqQLg6iG/FSR1uPpM1vR6mMffHJPg3cCeExje/ek=";
    };
    develocity = {
      name = "Develocity";
      description = "Gradle and Maven build scans from inside the IDE.";
      version = "1.3.1";
      url = "https://plugins.jetbrains.com/files/27471/1088367/develocity-intellij-plugin-1.3.1.zip";
      hash = "sha256-hZwIfu60h9FvIdPKPausWvjm4G79RjYJvjVYasxwHzc=";
    };
    spring-debugger = {
      name = "Spring Debugger";
      description = "Spring-aware debugging: beans, contexts, conditional config.";
      version = "262.8665.176";
      url = "https://plugins.jetbrains.com/files/25302/1102597/spring-debugger-262.8665.176.zip";
      hash = "sha256-hqJRZ0CQzNdMGFgAU3vgApUFr1rk99IN5YYmf6+80hA=";
    };
  };

  mkPluginOption = _id: def:
    lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "${def.name} ${def.version}. ${def.description}.";
    };

  # fetchzip for every entry, since each of these ships a directory. A plugin that
  # ships a bare JAR needs fetchurl with executable set, which addPlugins links
  # directly rather than as a directory. None in the catalogue do today, so the
  # table stays one shape until one does.
  srcOf = def:
    pkgs.fetchzip {
      inherit (def) url hash;
    };

  selectedPlugins =
    lib.mapAttrsToList (_id: srcOf)
    (lib.filterAttrs (id: _: cfg.plugins.${id}) pluginCatalog);

  allPlugins = selectedPlugins ++ cfg.extraPlugins;

  # addPlugins repackages the whole IDE, so skip it when nothing was selected.
  idePackage =
    if allPlugins == []
    then cfg.package
    else pkgs.jetbrains.plugins.addPlugins cfg.package allPlugins;
in {
  options.othrys.apps.idea = {
    enable = lib.mkEnableOption "IntelliJ IDEA";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.jetbrains.idea;
      defaultText = lib.literalExpression "pkgs.jetbrains.idea";
      description = ''
        IDEA distribution. JetBrains discontinued the Community edition in
        2025 and folded Ultimate into a single unfree build that a licence
        unlocks at runtime, so `pkgs.jetbrains.idea` is the current release
        and `pkgs.jetbrains.idea-community` no longer exists. Set
        `pkgs.jetbrains.idea-oss` for the free source build, which lags the
        unified one by a release or two.
      '';
    };

    plugins = lib.mapAttrs mkPluginOption pluginCatalog;

    extraPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        Plugins outside the curated catalogue, as derivations rather than names.
        nixpkgs removed resolution by plugin id and `addPlugins` throws on
        anything that is not a derivation, so each one is pinned by its
        marketplace URL and hash.

        Anything used on more than one host belongs in the catalogue in
        `idea.nix` instead, so the pin lives in one place.
      '';
      example = lib.literalExpression ''
        [
          (pkgs.fetchurl {
            executable = true; # a plugin shipping a bare JAR
            url = "https://plugins.jetbrains.com/files/7425/760442/WakaTime.jar";
            hash = "sha256-DobKZKokueqq0z75d2Fo3BD8mWX9+LpGdT9C7Eu2fHc=";
          })
        ]
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.othrys.apps.languages.java.enable;
        message = ''
          othrys.apps.idea: requires othrys.apps.languages.java.enable = true.

          IDEA needs a JDK on PATH, and its own "download JDK" action fetches
          dynamically linked binaries that will not run on NixOS. The languages
          module is the single toolchain signal for this fleet, so IDEA
          consumes the jdk/maven/gradle it already installs rather than
          bundling a divergent copy.
        '';
      }
    ];

    # Config, plugins and the project indexes. The index cache is the expensive
    # one, since without it every boot re-indexes each project from scratch, which is
    # minutes of CPU on anything non-trivial.
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/JetBrains"
        ".local/share/JetBrains"
        ".cache/JetBrains"
        ".java" # .userPrefs, written by the JVM preferences API
      ];
    };

    home-manager.users.${username} = {
      home.packages = [idePackage];
    };
  };
}
