# modules/apps/cli/ai/mcp/nixos.nix
# NixOS MCP server, providing NixOS and Nix package information
# Uses the nixpkgs-packaged mcp-nixos (locked via flake.lock, so no remote fetch).
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.mcp.nixos;
in {
  options.othrys.apps.ai.mcp.nixos = {
    enable = lib.mkEnableOption "NixOS MCP server";
  };

  config = lib.mkIf cfg.enable {
    othrys.internal.homeConfig."apps.ai.mcp.nixos" = {
      programs.mcp.servers.nixos = {
        command = lib.getExe pkgs.mcp-nixos;
        args = [];
      };

      # Pre-approve this server's read-only query tools. programs.claude-code
      # bundles programs.mcp.servers into a plugin named "claude-code-home-manager",
      # so the tools surface under the mcp__plugin_claude-code-home-manager_* namespace.
      programs.claude-code.settings.permissions.allow = [
        "mcp__plugin_claude-code-home-manager_nixos__nix"
        "mcp__plugin_claude-code-home-manager_nixos__nix_versions"
      ];
    };
  };
}
