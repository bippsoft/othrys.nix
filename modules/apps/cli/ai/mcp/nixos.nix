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
  inherit (import ./plugin-name.nix) pluginName;
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

      # Pre-approve this server's read-only query tools, under the plugin
      # name Home Manager gives the servers it bundles (see ./plugin-name.nix).
      programs.claude-code.settings.permissions.allow = [
        "mcp__plugin_${pluginName}_nixos__nix"
        "mcp__plugin_${pluginName}_nixos__nix_versions"
      ];
    };
  };
}
