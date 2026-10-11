# modules/apps/cli/gh.nix
# GitHub CLI, with its settings, the git credential helper and a token file for a headless host
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.gh;
  othrysTypes = import ../../lib/types.nix {inherit lib;};
  yamlFormat = pkgs.formats.yaml {};

  # gh takes a token from the GH_TOKEN environment variable and from no file
  # a secrets provider could write, so something has to turn the file into
  # that variable. A session variable would hand the token to every child of
  # every shell, and an argument would show it in /proc to every user. This
  # script reads the file with the shell's own redirection, so no other
  # program is started with it, exports the variable in its own process and
  # replaces that process with gh. The token then lives in gh and in what gh
  # starts. Only the path is interpolated here, so the store holds a file
  # name and never the token.
  #
  # A GH_TOKEN the caller already set is kept, since that caller chose it. A
  # file that cannot be read is reported and gh runs without it, so that
  # `gh auth status` describes the login the host really has.
  tokenWrapper = pkgs.writeShellScript "gh-token-wrapper" ''
    if [ -z "''${GH_TOKEN:-}" ]; then
      if [ -r ${lib.escapeShellArg cfg.tokenFile} ]; then
        GH_TOKEN="$(< ${lib.escapeShellArg cfg.tokenFile})"
        export GH_TOKEN
      else
        printf 'gh: token file %s is missing or unreadable, running without it\n' ${lib.escapeShellArg cfg.tokenFile} >&2
      fi
    fi
    exec ${pkgs.gh}/bin/gh "$@"
  '';

  # The real package with bin/gh swapped for the script above. Everything
  # else is linked through, so the completions and the man pages are the
  # ones gh ships. Home Manager points the git credential helper at this
  # package as well, which is how git over HTTPS finds the token on a host
  # that never ran `gh auth login`.
  wrappedPackage = pkgs.symlinkJoin {
    name = "gh-with-token-file-${pkgs.gh.version}";
    paths = [pkgs.gh];
    postBuild = ''
      rm $out/bin/gh
      ln -s ${tokenWrapper} $out/bin/gh
    '';
    passthru = {inherit tokenWrapper;};
    meta.mainProgram = "gh";
  };

  # Commands that read from GitHub and cannot change anything there. `gh api`
  # is left out because it sends any request, and so is every create, edit,
  # merge, close, comment and auth command.
  readOnlyCommands = [
    "gh issue view"
    "gh issue list"
    "gh pr view"
    "gh pr list"
    "gh pr diff"
    "gh pr checks"
    "gh run view"
    "gh run list"
    "gh repo view"
    "gh release view"
    "gh release list"
    "gh search"
  ];
in {
  options.othrys.apps.gh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Whether to install and configure the GitHub CLI. The module does not
        log in. `gh auth login` runs GitHub's OAuth device flow and stores
        the token in the Secret Service keyring when one is running, which
        `othrys.desktop.keyring` provides on a graphical host. Without a
        keyring it falls back to a plain file under `~/.config/gh`, which is
        persisted at mode 0700 under impermanence. A host with no browser and
        no keyring sets `tokenFile` instead.
      '';
    };

    gitProtocol = lib.mkOption {
      type = lib.types.enum ["ssh" "https"];
      default = "ssh";
      example = "https";
      description = ''
        Protocol `gh` uses for the git operations it runs itself, such as
        `gh repo clone` and `gh pr checkout`. It is written to `git_protocol`.
      '';
    };

    credentialHelper = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          Whether git asks `gh` for credentials on the hosts listed in
          `credentialHelper.hosts`, so that a clone, fetch or push over HTTPS
          uses the `gh` login and no second credential is stored. A remote
          reached over SSH is not affected.
        '';
      };

      hosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["https://github.com" "https://gist.github.com"];
        example = ["https://github.com" "https://github.example.com"];
        description = ''
          URLs git uses the `gh` credential helper for. Each becomes a
          `credential.<url>.helper` entry in the user's git configuration.
        '';
      };
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      example = lib.literalExpression "[ pkgs.gh-dash ]";
      description = ''
        `gh` extensions to install, each a package. They are linked under
        `~/.local/share/gh/extensions`, where `gh` looks for them.
      '';
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        co = "pr checkout";
        pv = "pr view";
      };
      description = ''
        Short names for `gh` commands, written to `aliases` in `config.yml`.
        The value is the command line without the leading `gh`.
      '';
    };

    settings = lib.mkOption {
      # What config.yml can carry, so a function or a package is refused here
      # by name instead of by the YAML generator.
      type = lib.types.attrsOf yamlFormat.type;
      default = {};
      example = {
        pager = "less -FRX";
        prompt = "disabled";
      };
      description = ''
        Further `config.yml` keys, merged over the ones this module writes. A
        key set here replaces the module's key of the same name whole, which
        includes `aliases`, `editor`, `git_protocol` and `prompt`.
      '';
    };

    editor = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = config.othrys.system.defaultEditor;
      defaultText = lib.literalExpression "config.othrys.system.defaultEditor";
      example = "nvim";
      description = ''
        Editor `gh` opens for an issue or pull request body, written to
        `editor`. Null leaves the choice to `gh`, which then reads
        `GIT_EDITOR`, `VISUAL` and `EDITOR` from the environment.
      '';
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr othrysTypes.secretPath;
      default = null;
      example = "/run/secrets/gh-token";
      description = ''
        Runtime path to a file holding a GitHub token, for a host with no
        browser and no keyring. The file is written by a secrets provider and
        has to be readable by the primary user.

        `gh` reads a token only from the `GH_TOKEN` environment variable, so
        when this is set the `gh` on the user's PATH is a wrapper. It reads
        the file into `GH_TOKEN` in its own process and then becomes the real
        `gh`. The token is in the environment of that `gh` and of the
        programs it starts, and it is not in the Nix store, the environment
        of the shell or a process argument. A `GH_TOKEN` that is already set
        is kept. When the file is missing or unreadable the wrapper says so
        on stderr and runs `gh` without it.
      '';
    };

    claudeCode.allowReadOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether read-only `gh` commands are added to the Claude Code
        allow-list when `othrys.apps.ai.claude-code.enable` is on, so an
        agent reads issues, pull requests, workflow runs, repositories,
        releases and search results without a prompt. Commands that write to
        GitHub stay prompted, and so does `gh api`, since it sends any
        request.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.persist."apps.gh" = {
      # hosts.yml names the account, and holds the OAuth token when no
      # keyring is running. 0700 so the directory is as private as the file
      # gh writes into it.
      user.directories = [
        {
          directory = ".config/gh";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.gh" = {
      programs = {
        gh =
          {
            enable = true;
            inherit (cfg) extensions;
            gitCredentialHelper = {
              inherit (cfg.credentialHelper) enable hosts;
            };
            settings =
              {
                git_protocol = cfg.gitProtocol;
                prompt = "enabled";
                inherit (cfg) aliases;
              }
              // lib.optionalAttrs (cfg.editor != null) {inherit (cfg) editor;}
              // cfg.settings;
          }
          // lib.optionalAttrs (cfg.tokenFile != null) {package = wrappedPackage;};

        # Every entry names the tool and a command prefix, the form
        # eval-claude-code holds the whole allow-list to. The list merges
        # with the one the Claude Code module writes.
        claude-code = lib.mkIf (cfg.claudeCode.allowReadOnly && config.othrys.apps.ai.claude-code.enable) {
          settings.permissions.allow = map (command: "Bash(${command}:*)") readOnlyCommands;
        };
      };
    };
  };
}
