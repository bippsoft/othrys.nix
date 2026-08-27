# modules/system/git.nix
# Git version control configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
  username = config.othrys.system.user.name;
  hmEnabled = config.othrys.system.users.homeManaged;
  cfg = config.othrys.system.git;
in {
  options.othrys.system.git = {
    enable = lib.mkEnableOption "Git version control";

    name = lib.mkOption {
      type = lib.types.str;
      description = "Git user name for commits.";
      example = "alice";
    };

    email = lib.mkOption {
      type = lib.types.str;
      description = "Git user email for commits.";
      example = "alice@example.com";
    };

    defaultBranch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Default branch name for new repositories.";
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        graph = "log --graph --oneline --decorate";
      };
      description = "Git aliases. Override or set to {} to opt out.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.git.enable = true;

    # Per-user git config only when othrys manages the user account
    # (see modules/system/nix.nix for the guard rationale).
    home-manager.users = lib.mkIf hmEnabled {
      ${username} = {
        home.packages = [pkgs.commitizen];

        programs.git = {
          enable = true;

          settings = {
            user = {
              inherit (cfg) name email;
            };

            init.defaultBranch = cfg.defaultBranch;
            pull.rebase = false;
            core.editor = config.othrys.system.defaultEditor;

            alias = cfg.aliases;
          };
        };
      };
    };
  };
}
