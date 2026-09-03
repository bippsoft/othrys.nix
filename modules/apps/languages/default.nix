# modules/apps/languages/default.nix
# Per-language development toolchains, the single "this host develops
# language X" signal (othrys.apps.languages.<lang>).
#
# Each language declares ONE canonical toolchain (server/formatter/extras),
# installed ONCE into the user's PATH via home-manager. Editor modules
# (nixvim, vscode) consume the same options to configure themselves and point
# at these shared binaries, and they never bundle their own divergent copies.
# This is the graphical/persistRoot pattern applied to languages, with one signal,
# curated swappable defaults, consumed everywhere (editors, shells, direnv,
# hooks all see identical tools).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.languages;

  # Canonical toolchain table. server = null means no standalone LSP binary
  # exists/is wanted for the language (editors bring their own where needed).
  languages = {
    bash = {
      name = "Bash";
      server = pkgs.bash-language-server;
      formatter = pkgs.shfmt;
      extraTools = [pkgs.shellcheck];
    };
    go = {
      name = "Go";
      server = pkgs.gopls;
      # The go toolchain ships gofmt (and is required for real Go work).
      formatter = pkgs.go;
      extraTools = [];
    };
    java = {
      name = "Java";
      # No standalone server, since vscode's redhat.java bundles jdtls and nixvim
      # deliberately runs without a Java LSP.
      server = null;
      formatter = pkgs.google-java-format;
      extraTools = [pkgs.jdk21 pkgs.maven pkgs.gradle];
    };
    lua = {
      name = "Lua";
      server = pkgs.lua-language-server;
      formatter = pkgs.stylua;
      extraTools = [];
    };
    nix = {
      name = "Nix";
      server = pkgs.nil;
      formatter = pkgs.alejandra;
      extraTools = [];
    };
    python = {
      name = "Python";
      server = pkgs.basedpyright;
      # ruff is both formatter and linter, the canonical modern Python stack
      # next to basedpyright.
      formatter = pkgs.ruff;
      extraTools = [];
    };
    rust = {
      name = "Rust";
      server = pkgs.rust-analyzer;
      formatter = pkgs.rustfmt;
      extraTools = [];
    };
    typescript = {
      name = "TypeScript";
      server = pkgs.typescript-language-server;
      formatter = pkgs.prettier;
      extraTools = [pkgs.typescript];
    };
  };

  mkLanguageOptions = _lang: def: {
    enable = lib.mkEnableOption "${def.name} language support (shared toolchain + editor wiring)";

    server = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = def.server;
      description = "Canonical ${def.name} language server, installed on the user's PATH and referenced by every editor. Null when the language has no standalone server.";
    };

    formatter = lib.mkOption {
      type = lib.types.package;
      default = def.formatter;
      description = "Canonical ${def.name} formatter, installed on the user's PATH and referenced by every editor.";
    };

    extraTools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = def.extraTools;
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
  # Migration aliases for the former pure-signal namespace.
  imports =
    lib.mapAttrsToList
    (lang: _: lib.mkRenamedOptionModule ["othrys" "apps" "lsp" lang "enable"] ["othrys" "apps" "languages" lang "enable"])
    languages;

  options.othrys.apps.languages = lib.mapAttrs mkLanguageOptions languages;

  # The shared toolchain lands on the user's PATH (home-manager scope) so
  # editors, terminals, direnv shells, and hooks all see the same binaries.
  config.othrys.internal.homeConfig."apps.languages".home.packages = lib.concatMap toolchainOf (lib.attrNames languages);
}
