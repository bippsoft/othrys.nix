# modules/apps/languages/default.nix
# Per-language development toolchains, the single "this host develops
# language X" signal (othrys.apps.languages.<lang>).
#
# Each language declares one canonical toolchain (server, formatter, extras),
# installed once into the user's PATH through Home Manager. The editor modules
# (nixvim, vscode) read the same options and name these packages by store
# path, so an override of `server` or `formatter` reaches every editor and the
# PATH together. This is the graphical/persistRoot pattern applied to
# languages, with one signal and curated swappable defaults that editors,
# shells, direnv and hooks all see.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.languages;

  # Canonical toolchain table. server = null means no standalone LSP binary
  # exists or is wanted for the language. An editor then configures no
  # external server for it and keeps whatever its own extension bundles.
  #
  # Each entry is a nixpkgs attribute name and not the package, so one string
  # yields both the option default and the `pkgs.<name>` text the generated
  # reference prints in place of a store path.
  languages = {
    bash = {
      name = "Bash";
      server = "bash-language-server";
      formatter = "shfmt";
      extraTools = ["shellcheck"];
    };
    go = {
      name = "Go";
      server = "gopls";
      # The go toolchain ships gofmt (and is required for real Go work).
      formatter = "go";
      extraTools = [];
    };
    java = {
      name = "Java";
      # No standalone server, since vscode's redhat.java bundles jdtls and nixvim
      # deliberately runs without a Java LSP.
      server = null;
      formatter = "google-java-format";
      extraTools = ["jdk21" "maven" "gradle"];
    };
    json = {
      name = "JSON";
      # Ships vscode-json-language-server beside the css, html and eslint
      # servers, and carries no meta.mainProgram, so editors name the binary.
      server = "vscode-langservers-extracted";
      formatter = "prettier";
      extraTools = [];
    };
    lua = {
      name = "Lua";
      server = "lua-language-server";
      formatter = "stylua";
      extraTools = [];
    };
    nix = {
      name = "Nix";
      server = "nil";
      formatter = "alejandra";
      extraTools = [];
    };
    python = {
      name = "Python";
      server = "basedpyright";
      # ruff is both formatter and linter, the canonical modern Python stack
      # next to basedpyright.
      formatter = "ruff";
      extraTools = [];
    };
    rust = {
      name = "Rust";
      server = "rust-analyzer";
      formatter = "rustfmt";
      extraTools = [];
    };
    typescript = {
      name = "TypeScript";
      server = "typescript-language-server";
      formatter = "prettier";
      extraTools = ["typescript"];
    };
    yaml = {
      name = "YAML";
      server = "yaml-language-server";
      formatter = "prettier";
      extraTools = [];
    };
  };

  mkLanguageOptions = _lang: def: {
    enable = lib.mkEnableOption "${def.name} language support (shared toolchain + editor wiring)";

    server = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default =
        if def.server == null
        then null
        else pkgs.${def.server};
      defaultText = lib.literalExpression (
        if def.server == null
        then "null"
        else "pkgs.${def.server}"
      );
      description = "Canonical ${def.name} language server, installed on the user's PATH and named by store path in every editor that takes an external server. Null leaves the language without a standalone server, and an editor then configures none.";
    };

    formatter = lib.mkOption {
      type = lib.types.package;
      default = pkgs.${def.formatter};
      defaultText = lib.literalExpression "pkgs.${def.formatter}";
      description = "Canonical ${def.name} formatter, installed on the user's PATH and named by store path in every editor. A replacement is run under the formatter definition that matches its executable name.";
    };

    extraTools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = map (name: pkgs.${name}) def.extraTools;
      defaultText = lib.literalExpression "[${lib.concatMapStringsSep " " (name: "pkgs.${name}") def.extraTools}]";
      description = "Additional ${def.name} tooling installed alongside the toolchain (linters, build tools, runtimes).";
    };
  };

  toolchainOf = lang: let
    c = cfg.${lang};
  in
    lib.optionals c.enable (
      lib.optional (c.server != null) c.server
      ++ [c.formatter]
      ++ c.extraTools
    );
in {
  # Migration aliases for the former pure-signal namespace, which held these
  # eight languages. Entries added since have no old name to alias.
  imports =
    map
    (lang: lib.mkRenamedOptionModule ["othrys" "apps" "lsp" lang "enable"] ["othrys" "apps" "languages" lang "enable"])
    ["bash" "go" "java" "lua" "nix" "python" "rust" "typescript"];

  options.othrys.apps.languages = lib.mapAttrs mkLanguageOptions languages;

  # The shared toolchain lands on the user's PATH (home-manager scope) so
  # editors, terminals, direnv shells, and hooks all see the same binaries.
  # The entry exists only while a language is enabled, since the registry
  # warns about every entry it skips on a host without a managed user, and an
  # empty package list is nothing to warn about.
  config.othrys.internal.homeConfig."apps.languages" = lib.mkIf (lib.any (lang: cfg.${lang}.enable) (lib.attrNames languages)) {
    home.packages = lib.concatMap toolchainOf (lib.attrNames languages);
  };
}
