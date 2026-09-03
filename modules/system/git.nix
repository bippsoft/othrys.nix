# modules/system/git.nix
# Git version control configuration
{
  config,
  lib,
  pkgs,
  ...
}: let
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

    othrys.internal.homeConfig."system.git" = {
      home.packages = [pkgs.commitizen];

      programs.git = {
        enable = true;

        settings = {
          user = {
            inherit (cfg) name email;
          };

          init.defaultBranch = cfg.defaultBranch;
          # A preference rather than a requirement, so mkDefault lets a
          # consumer set pull.rebase = true without lib.mkForce (the same
          # rule modules/services/ssh.nix states for its hardened settings).
          pull.rebase = lib.mkDefault false;
          core.editor = config.othrys.system.defaultEditor;

          alias = cfg.aliases;
        };
      };
    };
  };
}
