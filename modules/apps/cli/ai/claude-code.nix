# modules/apps/cli/ai/claude-code.nix
# Claude Code AI assistant with MCP servers via upstream home-manager integration
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.ai.claude-code;
  mcpCfg = config.othrys.apps.ai.mcp;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;

  # Type for file content that can be inline string or path
  fileContentType = lib.types.either lib.types.str lib.types.path;
in {
  options.othrys.apps.ai.claude-code = {
    enable = lib.mkEnableOption "Claude Code AI assistant";

    theme = lib.mkOption {
      type = lib.types.str;
      default = "dark";
      description = "Claude Code UI theme.";
    };

    permissions = {
      extraAllow = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional permission rules appended to the curated allow-list.";
        example = lib.literalExpression ''[ "Bash(cargo test:*)" ]'';
      };

      extraDeny = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional permission rules appended to the curated deny-list.";
      };
    };

    rules = lib.mkOption {
      type = lib.types.attrsOf fileContentType;
      default = {};
      description = "Rule markdown files for .claude/rules/.";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf fileContentType;
      default = {};
      description = "Agent markdown files for .claude/agents/.";
    };

    commands = lib.mkOption {
      type = lib.types.attrsOf fileContentType;
      default = {};
      description = "Command markdown files for .claude/commands/.";
    };

    hooks = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Hook scripts for .claude/hooks/.";
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf fileContentType;
      default = {};
      description = "Skill files for .claude/skills/.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username} = {
        directories = [
          ".claude"
        ];
        files = [
          ".claude.json"
        ];
      };
    };

    home-manager.users.${username} = {
      programs.claude-code = {
        enable = true;
        enableMcpIntegration = true;

        settings = {
          permissions = {
            allow =
              [
                "Edit"
                "Bash(git diff:*)"
                "Bash(git status:*)"
                "Bash(git add:*)"
                "Bash(git log:*)"
                "Bash(nix fmt:*)"
                "Bash(nix eval:*)"
                "Bash(just:*)"
                "Bash(mkdir:*)"
                "Bash(find:*)"
                # Each MCP server module contributes its own read-only tool
                # permissions to this list (see mcp/*.nix), and they merge in here.
              ]
              ++ cfg.permissions.extraAllow;

            deny =
              [
                "Read(./.env)"
                "Read(./.env.*)"
                "Read(./secrets/**)"
                "Bash(rm -rf:*)"
                "Bash(sudo:*)"
              ]
              ++ cfg.permissions.extraDeny;

            additionalDirectories = [];
            defaultMode = "acceptEdits";
          };

          hooks = {
            PostToolUse = [
              {
                matcher = "Edit|MultiEdit|Write";
                hooks = [
                  {
                    type = "command";
                    command = ''
                      if [[ "$CLAUDE_TOOL_INPUT_FILE_PATH" == *.nix ]]; then
                        nix fmt "$CLAUDE_TOOL_INPUT_FILE_PATH" 2>/dev/null || true
                      fi
                    '';
                  }
                ];
              }
            ];
          };

          inherit (cfg) theme;
          includeCoAuthoredBy = false;
        };

        inherit (mcpCfg) context;

        inherit (cfg) rules agents commands hooks skills;
      };

      home.sessionVariables = {
        DISABLE_AUTOUPDATER = "1";
      };

      # home.shellAliases propagates to every home-manager-enabled shell
      # (bash/zsh/fish), so never write per-shell alias sets from other modules.
      home.shellAliases = {
        cc = "claude";
      };
    };
  };
}
