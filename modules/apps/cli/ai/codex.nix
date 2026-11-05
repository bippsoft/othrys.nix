# modules/apps/cli/ai/codex.nix
# OpenAI Codex CLI with the shared skills, context and MCP servers via home-manager
{
  config,
  lib,
  pkgs,
  othrysInputs,
  ...
}: let
  cfg = config.othrys.apps.ai.codex;
  aiCfg = config.othrys.apps.ai;
  llmAgents = import ./llm-agents.nix {inherit lib pkgs othrysInputs;};
  toml = pkgs.formats.toml {};

  # Codex reports usage to OpenAI's analytics and its metrics exporter
  # follows that switch, /feedback uploads a session, and the startup check
  # asks GitHub for a newer release that a Nix-managed binary cannot install.
  quiet = {
    analytics.enabled = false;
    otel.metrics_exporter = "none";
    feedback.enabled = false;
    check_for_update_on_startup = false;
  };
in {
  options.othrys.apps.ai.codex = {
    enable = lib.mkEnableOption "OpenAI Codex CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = llmAgents.package "codex";
      defaultText = lib.literalMD "the `codex` package of the llm-agents flake this library locks";
      example = lib.literalExpression "pkgs.codex";
      description = ''
        The Codex package. The default tracks OpenAI's releases within hours
        and comes from cache.numtide.com, which the host then trusts.
      '';
    };

    disableTelemetry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Turn off Codex's analytics, its metrics exporter, `/feedback` uploads
        and the startup check for a newer release.
      '';
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = {};
      example = lib.literalExpression ''{ model = "gpt-5"; }'';
      description = ''
        Settings for `config.toml`, merged over what the module writes and
        winning over it.
      '';
    };

    skills = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str lib.types.path);
      default = {};
      description = ''
        Skills for Codex alone. They are written beside
        `othrys.apps.ai.skills`, and an entry of the same name here replaces
        the shared one for this tool.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.llmAgentsCache = true;

    # ~/.codex holds the sign-in where no keyring answers, the sessions, the
    # history and the state database, so the directory is 0700.
    othrys.internal.persist."apps.ai.codex" = {
      user.directories = [
        {
          directory = ".codex";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.ai.codex" = {
      programs.codex = {
        enable = true;
        inherit (cfg) package;
        enableMcpIntegration = true;
        # The declared settings are merged into a writable config.toml at
        # each activation, and declared values win. Codex records trusted
        # directories there, and a desktop client adds its hook approvals.
        mutableSettings = true;
        settings = lib.recursiveUpdate ({
            # The keyring the graphical hosts run, and the file where none
            # answers.
            cli_auth_credentials_store = "auto";
          }
          // lib.optionalAttrs cfg.disableTelemetry quiet)
        cfg.settings;
        context = aiCfg.context.text;
        # The shared skills first, so a skill declared for this tool under
        # the same name replaces the shared one.
        skills = aiCfg.skills // cfg.skills;
      };
    };
  };
}
