# modules/apps/cli/ai/mcp/default.nix
# Base MCP configuration, enabling upstream programs.mcp and shared context
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.ai.mcp;

  # Shared environment context for AI assistants
  globalContext = builtins.readFile ./nixos-context.md;

  # Check if any MCP server sub-module is enabled
  anyMcpEnabled =
    cfg.github.enable
    || cfg.nixos.enable
    || cfg.context7.enable;
in {
  imports = [
    ./github.nix
    ./nixos.nix
    ./context7.nix
  ];

  options.othrys.apps.ai.mcp = {
    # Individual server configs are defined in their own modules
    # They register themselves under home-manager's programs.mcp.servers.<name>

    context = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = globalContext;
      description = "Shared global context for AI assistants.";
    };
  };

  config = lib.mkIf anyMcpEnabled {
    othrys.internal.homeConfig."apps.ai.mcp".programs.mcp.enable = true;
  };
}
