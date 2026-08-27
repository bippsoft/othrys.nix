# modules/apps/cli/ai/mcp/github.nix
# GitHub MCP server via HTTP - uses {env:GITHUB_PAT} for runtime secret resolution
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.ai.mcp.github;
  secretPath = config.sops.secrets.${cfg.secret.path}.path;
  # Dynamic (read at shell start), so home.sessionVariables can't carry it;
  # bound once here and wired into each shell's init below.
  githubPatExport = ''
    [ -r "${secretPath}" ] && export GITHUB_PAT="$(< "${secretPath}")"
  '';
in {
  options.othrys.apps.ai.mcp.github = {
    enable = lib.mkEnableOption "GitHub MCP server";

    secret = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "api/github/pat";
        description = "Path to the secret within the sops file.";
      };

      sopsFile = lib.mkOption {
        # Deliberately lib.types.path, not othrysTypes.secretPath. This names an
        # ENCRYPTED sops file, which belongs in the store and is read at
        # evaluation, unlike the decrypted runtime paths that type guards.
        type = lib.types.path;
        default = config.othrys.system.secrets.secretFiles.common;
        defaultText = lib.literalExpression "config.othrys.system.secrets.secretFiles.common";
        description = "Sops file containing the GitHub PAT.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.othrys.system.secrets.enable;
        message = "othrys.apps.ai.mcp.github requires othrys.system.secrets.enable = true. The GitHub MCP server uses sops-nix for PAT secret management.";
      }
    ];

    # Declare the sops secret
    sops.secrets.${cfg.secret.path} = {
      inherit (cfg.secret) sopsFile;
    };

    home-manager.users.${username} = {
      # Register the server with an env var placeholder, resolved at runtime by MCP clients
      programs.mcp.servers.github = {
        url = "https://api.githubcopilot.com/mcp/";
        headers = {
          Authorization = "Bearer {env:GITHUB_PAT}";
        };
      };

      # Export GITHUB_PAT from the sops secret file in shell init
      programs.zsh.initContent = githubPatExport;
      programs.bash.initExtra = githubPatExport;
    };
  };
}
