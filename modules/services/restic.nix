# modules/services/restic.nix
# Restic backups (services.restic), one entry per named backup.
#
# Every credential-bearing field (repositoryFile,
# passwordFile, environmentFile, rcloneConfigFile) is a runtime FILE PATH, not an
# inline value, so point it at a secret provided by a secrets provider (e.g. a
# sops secret: `config.sops.secrets."backup/password".path`). Never pass a
# /nix/store path or an inline secret, since those are world-readable. `repository`
# (plain) is provided for non-sensitive locations only (a local disk path).
{
  config,
  lib,
  pkgs,
  ...
}: let
  othrysTypes = import ../lib/types.nix {inherit lib;};
  cfg = config.othrys.services.restic;

  backupType = lib.types.submodule {
    options = {
      paths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Paths to back up. Empty makes a prune-only job.";
        example = ["/var/lib/something" "/home/alice/Documents"];
      };

      repository = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/mnt/backup/restic";
        description = "Repository location for non-sensitive targets (e.g. a local path). Use repositoryFile when the URL carries a host or credentials.";
      };

      repositoryFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."backup/repo-url".path'';
        description = "Path to a runtime file containing the repository URL (a secrets-provider path). Mutually exclusive with repository.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."backup/repo-password".path'';
        description = "Path to a runtime file containing the repository password (a secrets-provider path). Omit only if the password is supplied via environmentFile (RESTIC_PASSWORD).";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        example = lib.literalExpression ''config.sops.secrets."backup/env".path'';
        description = "systemd EnvironmentFile with backend credentials (e.g. AWS_*/B2_* keys). Use a secrets-provider path.";
      };

      rcloneConfigFile = lib.mkOption {
        type = lib.types.nullOr othrysTypes.secretPath;
        default = null;
        description = "Path to an rclone config file for rclone backends. Use a secrets-provider path.";
      };

      exclude = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Restic exclude patterns.";
      };

      initialize = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create the repository on first run if it does not exist.";
      };

      timerConfig = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.anything);
        default = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        description = "systemd.timer schedule; null runs only when started manually.";
      };

      pruneOpts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 6"
        ];
        description = "Retention options for `restic forget --prune`, run after each backup.";
      };

      runCheck = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run `restic check` after the backup.";
      };

      checkOpts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["--read-data-subset=10%"];
        description = ''
          Options for `restic check` (when runCheck is set). Plain check
          verifies repository structure only, and never reads pack contents,
          so in-place bit corruption passes silently. Add
          `--read-data-subset=<n>%` (rotating partial content verification)
          or `--read-data` (full, every run) to actually verify data.
        '';
      };

      extraBackupArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra arguments passed to `restic backup`.";
      };

      backupPrepareCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = "Script run before the backup (e.g. quiesce a service or dump a database for a consistent snapshot).";
      };

      backupCleanupCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
        description = "Script run after the backup (e.g. resume the service quiesced in backupPrepareCommand).";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "User the backup runs as (must be able to read `paths`).";
      };
    };
  };
in {
  # ANCHOR: restic-options
  options.othrys.services.restic = {
    enable = lib.mkEnableOption "Restic backups";

    backups = lib.mkOption {
      type = lib.types.attrsOf backupType;
      default = {};
      description = "Named restic backups (maps to services.restic.backups.<name>).";
    };
  };
  # ANCHOR_END: restic-options

  config = lib.mkIf cfg.enable {
    # restic itself asserts exactly one repository source (repository /
    # repositoryFile / environmentFile). We only add the friendlier check that a
    # password has *some* source, since a missing one otherwise fails at runtime.
    assertions =
      lib.mapAttrsToList (name: b: {
        assertion = b.passwordFile != null || b.environmentFile != null;
        message = "othrys.services.restic.backups.${name}: set passwordFile (a secrets-provider path) or supply RESTIC_PASSWORD via environmentFile.";
      })
      cfg.backups;

    # Restic CLI for manual snapshot/restore against the same repositories.
    environment.systemPackages = [pkgs.restic];

    # A failed backup or repository check must reach a human, not die in the
    # journal (cross-module conditional, no hard dependency on notify).
    systemd.services = lib.mkIf config.othrys.services.notify.enable (
      lib.mapAttrs' (name: _:
        lib.nameValuePair "restic-backups-${name}" {
          onFailure = ["notify-failure@%n.service"];
        })
      cfg.backups
    );

    services.restic.backups =
      lib.mapAttrs (_: b: {
        inherit
          (b)
          paths
          repository
          repositoryFile
          passwordFile
          environmentFile
          rcloneConfigFile
          exclude
          initialize
          timerConfig
          pruneOpts
          runCheck
          checkOpts
          extraBackupArgs
          backupPrepareCommand
          backupCleanupCommand
          user
          ;
      })
      cfg.backups;
  };
}
