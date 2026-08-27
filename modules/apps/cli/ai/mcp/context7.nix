# modules/apps/cli/ai/mcp/context7.nix
# Context7 MCP server for library documentation over HTTP
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.ai.mcp.context7;
in {
  options.othrys.apps.ai.mcp.context7 = {
    enable = lib.mkEnableOption "Context7 MCP server";

    token = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Context7 API token (optional, works without one).";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${username} = {
      programs.mcp.servers.context7 = {
        url = "https://mcp.context7.com/mcp";
        headers =
          {
            Accept = "application/json, text/event-stream";
          }
          // lib.optionalAttrs (cfg.token != null) {
            CONTEXT7_API_KEY = cfg.token;
          };
      };

      # Pre-approve this server's read-only doc-lookup tools (bundled under the
      # claude-code-home-manager plugin namespace by programs.claude-code).
      programs.claude-code.settings.permissions.allow = [
        "mcp__plugin_claude-code-home-manager_context7__resolve-library-id"
        "mcp__plugin_claude-code-home-manager_context7__query-docs"
      ];
    };
  };
}
