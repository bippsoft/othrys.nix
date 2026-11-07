# modules/system/git.nix
# Git version control configuration
{lib, ...}: {
  options.othrys.system.git = {
    enable = lib.mkEnableOption "Git version control";

    # Null rather than no default. An option without a default fails with the
    # module system's "used but not defined" error, which names neither the
    # module nor what to set. The assertion in git.nixos.nix says both, and
    # only on a host where the identity is written.
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
}
