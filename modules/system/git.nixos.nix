# modules/system/git.nixos.nix
# The NixOS implementation of othrys.system.git
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.othrys.system.git;
in {
  imports = [./git.nix];

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
          # rule modules/services/ssh.nixos.nix states for its hardened settings).
          pull.rebase = lib.mkDefault false;
          core.editor = config.othrys.system.defaultEditor;

          alias = cfg.aliases;
        };
      };
    };
  };
}
