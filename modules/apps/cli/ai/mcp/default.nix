# modules/apps/cli/ai/mcp/default.nix
# Base MCP configuration, enabling upstream programs.mcp and shared context
{
  config,
  lib,
  ...
}: let
  cfg = config.othrys.apps.ai.mcp;

  # Shared environment context for AI assistants. The root wipe is a
  # property of the host, so the line about it is rendered from the host's
  # impermanence setting rather than told to every host. It is appended to
  # the store bullet, the last of the "cannot do" list, and eval-claude-code
  # reads the rendered text back so an edit to that bullet is noticed.
  storeBullet = "- **No modifying /nix/store**: It's read-only and immutable\n";
  impermanenceBullet =
    lib.optionalString config.othrys.system.impermanence.enable
    "- **No persistent writes outside $HOME**: the root filesystem is wiped on every boot, and only paths declared under `environment.persistence` survive it\n";
  globalContext = lib.replaceStrings [storeBullet] [(storeBullet + impermanenceBullet)] (builtins.readFile ./nixos-context.md);

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
