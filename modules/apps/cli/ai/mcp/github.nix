# modules/apps/cli/ai/mcp/github.nix
# GitHub MCP server, run locally over stdio with a file-backed PAT
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.apps.ai.mcp.github;
  secretPath = config.sops.secrets.${cfg.secret.path}.path;
in {
  options.othrys.apps.ai.mcp.github = {
    enable = lib.mkEnableOption "GitHub MCP server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.github-mcp-server;
      defaultText = lib.literalExpression "pkgs.github-mcp-server";
      description = "GitHub MCP server package run over stdio.";
    };

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

    othrys.internal.homeConfig."apps.ai.mcp.github" = {
      # A local stdio server rather than the hosted HTTP endpoint, because
      # programs.mcp only accepts file-backed env on local servers. Upstream
      # turns the file reference into a wrapper that reads the sops path at
      # launch and execs the server, so the token exists only in that
      # process. The previous form exported it at shell init, where every
      # child of every interactive shell inherited it.
      programs.mcp.servers.github = {
        command = lib.getExe cfg.package;
        args = ["stdio"];
        env.GITHUB_PERSONAL_ACCESS_TOKEN.file = secretPath;
      };
    };
  };
}
