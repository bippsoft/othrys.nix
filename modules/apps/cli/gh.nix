# modules/apps/cli/gh.nix
# GitHub CLI
{
  config,
  lib,
  ...
}: let
  username = config.othrys.system.user.name;
  usersEnabled = config.othrys.system.users.enable;
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
    environment.persistence.${persistRoot} = lib.mkIf (impermanenceEnabled && usersEnabled) {
      # hosts.yml holds the OAuth token. 0700 so the directory is as private
      # as the file gh writes into it.
      users.${username}.directories = [
        {
          directory = ".config/gh";
          mode = "0700";
        }
      ];
    };

    othrys.internal.homeConfig."apps.gh" = {
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
