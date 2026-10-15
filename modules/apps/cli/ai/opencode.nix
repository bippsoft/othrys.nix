# modules/apps/cli/ai/opencode.nix
# OpenCode AI assistant with the shared skills, context and MCP servers
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.opencode;
  aiCfg = config.othrys.apps.ai;

  jsonFormat = pkgs.formats.json {};

  # Type for file content that can be inline string or path
  fileContentType = lib.types.either lib.types.str lib.types.path;

  action = lib.types.enum ["allow" "ask" "deny"];

  # OpenCode reads ~/.claude/skills beside its own directory unless told not
  # to. On a host where Claude Code is enabled the shared skills are already
  # there, so writing them a second time would list each one twice.
  viaClaude = cfg.claudeCompat && aiCfg.claude-code.enable;
  sharedSkills = lib.optionalAttrs (!viaClaude) aiCfg.skills;

  ollamaCfg = aiCfg.ollama;

  curated =
    {
      # The package comes from the store, which the tool cannot replace.
      autoupdate = false;

      inherit (cfg) share;

      # These rules are ergonomics, not a security boundary, for the reason
      # given in ./claude-code.nix. A pattern matches a command string and a
      # string has endless spellings. OpenCode's own default allows every
      # edit and every command, so the two entries below are what makes it
      # prompt at all.
      #
      # The last matching pattern wins, and the file is written with its
      # keys in alphabetical order. "*" sorts before every letter, so the
      # catch-all comes first and each named command overrides it.
      permission = {
        inherit (cfg.permissions) edit;
        bash =
          {
            "*" = "ask";
            "git diff*" = "allow";
            "git status*" = "allow";
            "git add*" = "allow";
            "git log*" = "allow";
            "mkdir *" = "allow";
            "rm -rf*" = "deny";
            "sudo *" = "deny";
          }
          // cfg.permissions.extraBash;
      };
    }
    // lib.optionalAttrs (cfg.ollama.enable && ollamaCfg.enable) {
      # Ollama serves the OpenAI wire format under /v1, on the address
      # ./ollama.nix exports as OLLAMA_HOST.
      provider.ollama = {
        npm = "@ai-sdk/openai-compatible";
        name = "Ollama (local)";
        options.baseURL = "http://127.0.0.1:11434/v1";
        models = lib.genAttrs ollamaCfg.loadModels (name: {inherit name;});
      };
    };
in {
  options.othrys.apps.ai.opencode = {
    enable = lib.mkEnableOption "OpenCode AI assistant";

    package = lib.mkPackageOption pkgs "opencode" {};

    share = lib.mkOption {
      type = lib.types.enum ["manual" "auto" "disabled"];
      default = "disabled";
      description = ''
        Session sharing mode. "manual" allows sharing through `/share`,
        "auto" shares new conversations automatically, and "disabled"
        prevents sharing. Shared sessions are uploaded to a public URL,
        so this module disables sharing instead of OpenCode's "manual"
        default. `settings.share` overrides this value.
      '';
    };

    claudeCompat = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether OpenCode reads Claude Code's files, which are
        `~/.claude/skills`, `~/.claude/CLAUDE.md` and the `.claude` directory
        of a project. It does so by default. On a host that also enables
        `othrys.apps.ai.claude-code`, the shared skills then reach OpenCode
        through `~/.claude/skills` and are not written a second time, and the
        skills declared for Claude Code alone are visible to OpenCode as well.

        Turning it off sets `OPENCODE_DISABLE_CLAUDE_CODE`. OpenCode then
        reads its own directory only, and the shared skills are written
        there.
      '';
    };

    permissions = {
      edit = lib.mkOption {
        type = action;
        default = "ask";
        description = ''
          What OpenCode does before it changes a file. "ask" prompts, and
          "allow" is OpenCode's own default, which writes without asking in
          whichever repository the session was started from.
        '';
      };

      extraBash = lib.mkOption {
        type = lib.types.attrsOf action;
        default = {};
        example = lib.literalExpression ''{ "cargo test*" = "allow"; }'';
        description = ''
          Command patterns merged over the curated map, which prompts for
          every command but a few read-only git commands. `*` matches any
          run of characters. The last matching pattern wins and the patterns
          are written in alphabetical order.
        '';
      };
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf fileContentType;
      default = {};
      description = ''
        Skills for OpenCode alone, written beside `othrys.apps.ai.skills`. An
        entry of the same name here replaces the shared one for this tool.
      '';
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf fileContentType;
      default = {};
      description = "Agent markdown files for ~/.config/opencode/agents/.";
    };

    commands = lib.mkOption {
      type = lib.types.attrsOf fileContentType;
      default = {};
      description = "Command markdown files for ~/.config/opencode/commands/.";
    };

    ollama.enable =
      lib.mkEnableOption "a provider entry for the local Ollama server, on a host that enables `othrys.apps.ai.ollama`. Its models are the ones in `othrys.apps.ai.ollama.loadModels`"
      // {default = true;};

    settings = lib.mkOption {
      inherit (jsonFormat) type;
      default = {};
      example = lib.literalExpression ''
        {
          model = "anthropic/claude-sonnet-4-5";
          permission.webfetch = "ask";
        }
      '';
      description = ''
        Settings merged over the ones this module writes to
        `~/.config/opencode/opencode.json`, so a value here wins. See
        <https://opencode.ai/docs/config/>.
      '';
    };

    tui = lib.mkOption {
      inherit (jsonFormat) type;
      default = {};
      example = lib.literalExpression ''{ theme = "system"; }'';
      description = "Settings written to `~/.config/opencode/tui.json`, such as the theme and the key bindings.";
    };
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.persist."apps.ai.opencode" = {
      user = {
        # .local/share/opencode holds auth.json, the provider credentials,
        # beside the sessions, so the directory is 0700.
        directories = [
          {
            directory = ".local/share/opencode";
            mode = "0700";
          }
          ".local/state/opencode"
        ];
      };
    };

    othrys.internal.homeConfig."apps.ai.opencode" = {
      programs.opencode = {
        enable = true;
        inherit (cfg) package tui agents commands;
        enableMcpIntegration = true;

        settings = lib.recursiveUpdate curated cfg.settings;

        context = aiCfg.context.text;

        # The shared skills first, so a skill declared for this tool under
        # the same name replaces the shared one.
        skills = sharedSkills // cfg.skills;
      };

      home.sessionVariables = lib.mkIf (!cfg.claudeCompat) {
        OPENCODE_DISABLE_CLAUDE_CODE = "1";
      };
    };
  };
}
