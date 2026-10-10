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

    # Null rather than no default. An option without a default fails with the
    # module system's "used but not defined" error, which names neither the
    # module nor what to set. The assertion below says both, and only on a
    # host where the identity is written.
    name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Git user name for commits. Required, together with `email`, on a host
        where Home Manager manages the primary user, since that is where the
        identity is written. A host without a managed user installs git and
        reads neither.
      '';
      example = "alice";
    };

    email = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Git user email for commits. Required, together with `name`, on a host
        where Home Manager manages the primary user.
      '';
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
    # The identity only reaches a file through the Home Manager configuration
    # below, so the requirement follows homeManaged. A headless host enables
    # git for the binary and states no author.
    assertions = [
      {
        assertion = !config.othrys.system.users.homeManaged || (cfg.name != null && cfg.email != null);
        message = "othrys.system.git: set othrys.system.git.name and othrys.system.git.email. Home Manager writes them as the commit author for the primary user, and git refuses to commit without one.";
      }
    ];

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
