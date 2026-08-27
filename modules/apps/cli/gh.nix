# modules/apps/cli/gh.nix
# GitHub CLI
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  cfg = config.othrys.apps.gh;
  impermanenceEnabled = config.othrys.system.impermanence.enable;
  persistRoot = config.othrys.system.impermanence.persistRoot;
in {
  options.othrys.apps.gh = {
    enable = lib.mkEnableOption "GitHub CLI";

    gitProtocol = lib.mkOption {
      type = lib.types.enum ["ssh" "https"];
      default = "ssh";
      description = "Git protocol for GitHub operations.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.persistence.${persistRoot} = lib.mkIf impermanenceEnabled {
      users.${username}.directories = [
        ".config/gh"
      ];
    };

    home-manager.users.${username} = {
      programs.gh = {
        enable = true;
        settings = {
          git_protocol = cfg.gitProtocol;
          prompt = "enabled";
        };
      };
    };
  };
}
