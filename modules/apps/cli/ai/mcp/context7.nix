# modules/apps/cli/ai/mcp/context7.nix
# Context7 MCP server for library documentation over HTTP
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.ai.mcp.context7;
  inherit (import ./plugin-name.nix) pluginName;
in {
  imports = [
    (lib.mkRemovedOptionModule ["othrys" "apps" "ai" "mcp" "context7" "token"] "The token was written into the MCP config in the world-readable Nix store. Context7 works without one; a host that needs one runs the server through a launcher that reads the key from a secrets-provider file, as the github server does.")
  ];

  options.othrys.apps.ai.mcp.context7 = {
    enable = lib.mkEnableOption "Context7 MCP server";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.homeConfig."apps.ai.mcp.context7" = {
      programs.mcp.servers.context7 = {
        url = "https://mcp.context7.com/mcp";
        headers.Accept = "application/json, text/event-stream";
      };

      # Pre-approve this server's read-only doc-lookup tools, under the
      # plugin name Home Manager gives the servers it bundles.
      programs.claude-code.settings.permissions.allow = [
        "mcp__plugin_${pluginName}_context7__resolve-library-id"
        "mcp__plugin_${pluginName}_context7__query-docs"
      ];
    };
  };
}
