# flake/checks/languages-eval.nix
# CORE. What the two editors take from the language registry, read back from
# evaluated hosts. A formatter named by a string in one editor and by store
# path in the other evaluates either way, and so does a plugin set up twice,
# so only the rendered settings show which binary an editor runs.
{
  lib,
  hostConfig,
  mkExpectations,
  functioningHost,
}: let
  host = extra:
    hostConfig [
      functioningHost
      {
        othrys.system.stylix.enable = true;
        othrys.desktop.graphical = true;
        othrys.apps.nixvim.enable = true;
        othrys.apps.vscode.enable = true;
      }
      extra
    ];

  # Every language on, with the Nix formatter replaced by a package whose
  # executable differs from the default's.
  overridden = host ({pkgs, ...}: {
    othrys.apps.languages = {
      bash.enable = true;
      go.enable = true;
      java.enable = true;
      json.enable = true;
      lua.enable = true;
      nix = {
        enable = true;
        formatter = pkgs.nixfmt;
      };
      python.enable = true;
      rust.enable = true;
      typescript.enable = true;
      yaml.enable = true;
    };
  });

  # Servers set to null where an editor would otherwise name one, shellcheck
  # taken out of the bash tools, and JSON and YAML left off beside TypeScript.
  serverless = host {
    othrys.apps.languages = {
      bash = {
        enable = true;
        extraTools = [];
      };
      go = {
        enable = true;
        server = null;
      };
      lua = {
        enable = true;
        server = null;
      };
      nix = {
        enable = true;
        server = null;
      };
      rust = {
        enable = true;
        server = null;
      };
      typescript.enable = true;
    };
  };

  immutable = host {othrys.apps.vscode.mutableExtensionsDir = false;};

  home = cfg: cfg.home-manager.users.${cfg.othrys.system.user.name};
  registry = cfg: cfg.othrys.apps.languages;
  nixvim = cfg: (home cfg).programs.nixvim;
  conform = cfg: (nixvim cfg).plugins.conform-nvim.settings;
  servers = cfg: (nixvim cfg).lsp.servers;
  profile = cfg: (home cfg).programs.vscodium.profiles.default;
  settings = cfg: (profile cfg).userSettings;
  hasExtension = id: cfg: builtins.any (e: (e.vscodeExtUniqueId or "") == id) (profile cfg).extensions;

  inStore = lib.hasPrefix "${builtins.storeDir}/";
  occurrences = needle: text: builtins.length (lib.splitString needle text) - 1;
  # hasInfix matches by regular expression, which refuses a string that
  # carries store context, so both sides are compared as plain text.
  plain = builtins.unsafeDiscardStringContext;
  init = plain (nixvim overridden).content;

  langs = registry overridden;
  shellcheck = builtins.head langs.bash.extraTools;
in
  mkExpectations "othrys-eval-languages" {
    "nixvim runs the replacement nix formatter by store path" = (conform overridden).formatters.nixfmt.command == lib.getExe langs.nix.formatter && lib.hasSuffix "/bin/nixfmt" (conform overridden).formatters.nixfmt.command;
    "nixvim names the replacement for nix buffers and drops the default" = (conform overridden).formatters_by_ft.nix == ["nixfmt"] && !((conform overridden).formatters ? alejandra);
    "the replacement's store path reaches the rendered init" = lib.hasInfix (plain (lib.getExe langs.nix.formatter)) init;
    "every nixvim formatter command is a store path" = builtins.all (f: inStore f.command) (builtins.attrValues (conform overridden).formatters);
    "every nixvim filetype names a formatter that has a command" = builtins.all (names: builtins.all (name: (conform overridden).formatters ? ${name}) names) (builtins.attrValues (conform overridden).formatters_by_ft);
    "nixvim formats python through ruff's format definition" = (conform overridden).formatters_by_ft.python == ["ruff_format"] && (conform overridden).formatters.ruff_format.command == lib.getExe langs.python.formatter;
    "nixvim formats go with the gofmt beside the toolchain" = (conform overridden).formatters.gofmt.command == lib.getExe' langs.go.formatter "gofmt";
    "nixvim formats json and yaml with the registry formatter" = (conform overridden).formatters_by_ft.json == ["prettier"] && (conform overridden).formatters_by_ft.yaml == ["prettier"] && (conform overridden).formatters.prettier.command == lib.getExe langs.json.formatter;
    "nixvim runs the json and yaml servers" = (servers overridden).jsonls.enable && (servers overridden).jsonls.package == langs.json.server && (servers overridden).yamlls.enable && (servers overridden).yamlls.package == langs.yaml.server;
    "the json server command names its binary in the registry package" = builtins.head (servers overridden).jsonls.config.cmd == "${langs.json.server}/bin/vscode-json-language-server";
    "typescript alone configures neither json nor yaml in nixvim" = !((conform serverless).formatters_by_ft ? json) && !((conform serverless).formatters_by_ft ? yaml) && !(servers serverless).jsonls.enable && !(servers serverless).yamlls.enable;
    "typescript alone configures neither json nor yaml in vscode" = !((settings serverless) ? "[json]") && !((settings serverless) ? "[yaml]") && !hasExtension "redhat.vscode-yaml" serverless;
    "autopairs is set up once in the rendered init" = occurrences "require('nvim-autopairs').setup(" init + occurrences "require(\"nvim-autopairs\").setup(" init == 1;
    "the one autopairs setup carries the settings" = lib.hasInfix "snacks_picker_input" init && lib.hasInfix "PmenuSel" init;

    "vscode formats nix with the replacement" = (settings overridden)."nix.formatterPath" == lib.getExe langs.nix.formatter;
    "vscode runs the registry nix and rust servers" = (settings overridden)."nix.serverPath" == lib.getExe langs.nix.server && (settings overridden)."nix.enableLanguageServer" && (settings overridden)."rust-analyzer.server.path" == lib.getExe langs.rust.server;
    "vscode runs the registry lua server" = (settings overridden)."Lua.misc.executablePath" == lib.getExe langs.lua.server;
    "vscode runs the registry ruff" = (settings overridden)."ruff.path" == [(lib.getExe langs.python.formatter)];
    "vscode runs the registry gopls and gofmt" = (settings overridden)."go.alternateTools".gopls == lib.getExe langs.go.server && (settings overridden)."go.alternateTools".customFormatter == lib.getExe' langs.go.formatter "gofmt" && (settings overridden)."go.formatTool" == "custom";
    "vscode runs the registry shfmt and shellcheck" = (settings overridden)."bashIde.shfmt.path" == lib.getExe langs.bash.formatter && (settings overridden)."shellcheck.executablePath" == lib.getExe shellcheck && (settings overridden)."bashIde.shellcheckPath" == lib.getExe shellcheck;
    "vscode loads prettier from the registry package" = lib.hasPrefix "${langs.typescript.formatter}/" (settings overridden)."prettier.prettierPath" && hasExtension "esbenp.prettier-vscode" overridden;
    "vscode formats json and yaml with prettier" = (settings overridden)."[json]"."editor.defaultFormatter" == "esbenp.prettier-vscode" && (settings overridden)."[yaml]"."editor.defaultFormatter" == "esbenp.prettier-vscode" && hasExtension "redhat.vscode-yaml" overridden;

    "a null server leaves vscode without a server path" = !((settings serverless) ? "nix.serverPath") && !(settings serverless)."nix.enableLanguageServer" && !((settings serverless) ? "rust-analyzer.server.path") && !((settings serverless) ? "Lua.misc.executablePath") && !((settings serverless)."go.alternateTools" ? gopls);
    "a null server keeps the vscode formatter" = inStore (settings serverless)."nix.formatterPath";
    "vscode keeps a writable extensions directory by default" = (home overridden).programs.vscodium.mutableExtensionsDir;
    "a host can make the vscode extensions directory immutable" = !(home immutable).programs.vscodium.mutableExtensionsDir;
    "a null server enables no nixvim server" = !(servers serverless).nil_ls.enable && !(servers serverless).rust_analyzer.enable && !(servers serverless).lua_ls.enable && !(servers serverless).gopls.enable;
    "bash without shellcheck in its tools sets no shellcheck path" = !((settings serverless) ? "shellcheck.executablePath") && !((settings serverless) ? "bashIde.shellcheckPath");
    "a host with null servers raises no assertion" = builtins.all (a: a.assertion) serverless.assertions;
  }
