# flake/checks/gh-eval.nix
# CORE. What the gh module hands Home Manager, read back from evaluated
# hosts. The settings file, the git credential helper, the wrapper a token
# file puts in front of gh and the commands Claude Code runs without a prompt
# are all values a host evaluates cleanly with whether or not they are right.
{
  lib,
  hostConfig,
  mkExpectations,
  functioningHost,
  bootBase,
}: let
  tokenFile = "/run/secrets/gh-token";

  # Every option past its default, beside Claude Code.
  configured = hostConfig [
    functioningHost
    {
      othrys.system = {
        nix.allowUnfree = true;
        defaultEditor = "hx";
      };
      othrys.apps = {
        ai.claude-code.enable = true;
        gh = {
          enable = true;
          aliases.co = "pr checkout";
          settings = {
            prompt = "disabled";
            pager = "cat";
          };
        };
      };
    }
  ];

  # A token file, another credential host, and the allow-list entries
  # declined on a host that runs Claude Code.
  withToken = hostConfig [
    functioningHost
    {
      othrys.system.nix.allowUnfree = true;
      othrys.apps = {
        ai.claude-code.enable = true;
        gh = {
          enable = true;
          inherit tokenFile;
          credentialHelper.hosts = ["https://github.example.com"];
          claudeCode.allowReadOnly = false;
        };
      };
    }
  ];

  # The bare enable, on a host without Claude Code.
  plain = hostConfig [
    functioningHost
    {othrys.apps.gh.enable = true;}
  ];

  # A declared user name with no account and no Home Manager, which is the
  # host a token file exists for.
  headless = hostConfig [
    bootBase
    {
      othrys.system.nix = {
        enable = true;
        stateVersion = "26.05";
      };
      othrys.apps.gh = {
        enable = true;
        inherit tokenFile;
      };
    }
  ];

  hm = h: h.home-manager.users.${h.othrys.system.user.name};
  gh = h: (hm h).programs.gh;
  settings = h: (gh h).settings;
  credential = h: (hm h).programs.git.settings.credential;
  helperOf = h: url: lib.toList (credential h).${url}.helper;
  installs = h: builtins.any (p: (p.name or "") == (gh h).package.name) (hm h).home.packages;

  wrapper = (gh withToken).package;
  script = wrapper.tokenWrapper.text;
  # The prefixes GitHub gives its tokens. None may appear in the script.
  tokenPrefixes = ["ghp_" "gho_" "ghu_" "ghs_" "ghr_" "github_pat_"];

  # settings.permissions is absent on a host without Claude Code.
  allow = h: (hm h).programs.claude-code.settings.permissions.allow or [];
  ghEntries = h: builtins.filter (lib.hasPrefix "Bash(gh ") (allow h);
  readOnly = map (command: "Bash(gh ${command}:*)") [
    "issue view"
    "issue list"
    "pr view"
    "pr list"
    "pr diff"
    "pr checks"
    "run view"
    "run list"
    "repo view"
    "release view"
    "release list"
    "search"
  ];
  writes = e: builtins.match "Bash[(]gh (api|auth|.* (create|edit|merge|close|comment|delete))[: ].*" e != null;
in
  mkExpectations "othrys-eval-gh" {
    "the git protocol is ssh by default" = (settings plain).git_protocol == "ssh";
    "the editor follows defaultEditor" = (settings configured).editor == "hx" && (settings plain).editor == plain.othrys.system.defaultEditor;
    "an alias reaches the settings" = (settings configured).aliases.co == "pr checkout";
    "a passthrough key is added" = (settings configured).pager == "cat";
    "a passthrough key overrides the module's default" = (settings configured).prompt == "disabled" && (settings plain).prompt == "enabled";

    "git asks gh for credentials on both default hosts" = builtins.all (url: builtins.any (lib.hasSuffix "/bin/gh auth git-credential") (helperOf plain url)) ["https://github.com" "https://gist.github.com"];
    "the credential hosts are the ones the option names" = builtins.attrNames (credential withToken) == ["https://github.example.com"];
    "the credential helper runs the wrapper on a host with a token file" = builtins.elem "${wrapper}/bin/gh auth git-credential" (helperOf withToken "https://github.example.com");

    "a token file puts the wrapper on the PATH" = lib.hasPrefix "gh-with-token-file" wrapper.name && installs withToken;
    "the wrapper is still named gh" = wrapper.meta.mainProgram == "gh";
    "the wrapper reads the token file into GH_TOKEN" = lib.hasInfix "GH_TOKEN=\"$(< ${tokenFile})\"" script && lib.hasInfix "export GH_TOKEN" script;
    "the wrapper hands its arguments to the real gh" = lib.hasInfix "/bin/gh \"$@\"" script;
    "the wrapper reports a token file it cannot read" = lib.hasInfix "missing or unreadable" script && lib.hasInfix ">&2" script;
    "the wrapper holds no token" = !builtins.any (prefix: lib.hasInfix prefix script) tokenPrefixes;
    "a host without a token file installs the plain package" = ((gh plain).package.pname or "") == "gh" && !((gh plain).package ? tokenWrapper) && installs plain;

    "the read-only commands are pre-approved beside Claude Code" = builtins.all (e: builtins.elem e (allow configured)) readOnly;
    "every gh entry names a tool and a specifier" = builtins.all (e: builtins.match "Bash[(]gh [a-z ]+:[*][)]" e != null) (ghEntries configured);
    "no other gh command is pre-approved" = builtins.length (ghEntries configured) == builtins.length readOnly;
    "gh api and the writing commands are not pre-approved" = !builtins.any writes (allow configured);
    "allowReadOnly off pre-approves no gh command" = ghEntries withToken == [];
    "a host without Claude Code carries no gh entry" = ghEntries plain == [];

    "a headless host without Home Manager evaluates with the module on" = headless.system.build.toplevel.drvPath != null;
  }
