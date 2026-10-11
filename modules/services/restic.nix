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

  sandbox = import ../lib/sandbox.nix;
  notifyCfg = config.othrys.services.notify;

  # `repository` is written into the unit's environment, which sits in the
  # world-readable store. Three shapes put a credential there. The first is
  # scheme://user:password@host under any scheme. The second is anything
  # before the `@` of an http or https URL, where that part is sent as HTTP
  # authentication, so a lone token is a credential as well. An sftp URL
  # names only the login there and is left alone. The third is a query
  # parameter named for a token, a key, a secret, a password or a signature.
  credentialShapes = [
    ".*://[^/@]*:[^/@]*@.*"
    ".*https?://[^/?#]*@.*"
    ".*[?&][^=&]*([Tt]oken|[Kk]ey|[Ss]ecret|[Pp]ass|[Ss]ig|[Aa]uth|[Cc]redential)[^=&]*=.*"
  ];
  carriesCredentials = repository: repository != null && builtins.any (shape: builtins.match shape repository != null) credentialShapes;

  # The exit status the check step turns a failed `restic check` into.
  # restic's documented statuses are 1, 3, 10, 11, 12 and 130, so the failure
  # hook can tell a failed check from a failed backup by this number alone.
  checkFailedStatus = 90;

  # The check runs as a step of its own behind upstream's backup and prune
  # commands, which is where upstream's `runCheck` puts it too. Upstream's
  # copy is turned off below, since its failure cannot be told apart from
  # that of the commands before it. The options are joined unquoted, the way
  # upstream hands them to systemd, so an entry such as "--read-data-subset 5%"
  # still splits into two arguments. The package and the `-o` options are
  # read from upstream's side, so a host that sets either there gets the same
  # command for the check as for the backup.
  checkStep = name: b: let
    upstream = config.services.restic.backups.${name};
  in
    pkgs.writeShellScript "restic-backups-${name}-check" ''
      ${lib.getExe upstream.package}${lib.concatMapStrings (arg: " -o ${arg}") upstream.extraOptions} check ${lib.concatStringsSep " " b.checkOpts} || exit ${toString checkFailedStatus}
    '';

  # systemd hands a unit started through OnFailure the exit status of the
  # process that failed, as MONITOR_EXIT_STATUS. The line is written to the
  # journal as well, so the reason is on the host when the notification
  # cannot be sent.
  failureScript = pkgs.writeShellScript "restic-notify-failure" ''
    unit="$1"
    host=${lib.escapeShellArg config.networking.hostName}
    if [ "''${MONITOR_EXIT_STATUS:-}" = ${toString checkFailedStatus} ]; then
      title="$unit: repository check failed on $host"
      message="the backup completed and the repository check after it failed, so the new snapshot exists and the repository needs attention"
    else
      title="$unit: backup failed on $host"
      message="the backup or the prune after it failed, and no repository check ran"
    fi
    echo "$unit: $message" >&2
    exec /run/current-system/sw/bin/othrys-notify "$title" "$message"
  '';

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
        description = ''
          Repository location for non-sensitive targets (e.g. a local path).
          The value is written to the unit file in the store, so a URL that
          carries a credential is rejected. That covers `user:password@`
          under any scheme, anything before the `@` of an `http` or `https`
          URL, a lone token included, and a query parameter named for a token,
          a key, a secret, a password or a signature. Use repositoryFile when
          the URL carries a host or credentials.
        '';
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
        description = ''
          Create the repository on first run when none exists at the
          location. Where several hosts back up into one repository, leave
          this on for one host and set it to `false` on the rest. Two first
          runs can otherwise both initialise the repository, and a host
          pointed at the wrong location creates an empty repository there
          instead of failing.
        '';
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
        default = true;
        description = ''
          Run `restic check` after the backup, so a damaged repository fails
          the backup unit instead of being found at restore time. The check
          reads from the repository backend on every run. Set this to `false`
          where that read is not wanted.
        '';
      };

      checkOpts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["--read-data-subset=5%"];
        example = ["--read-data"];
        description = ''
          Options for `restic check` (when runCheck is set). Plain check
          verifies repository structure only, and never reads pack contents,
          so in-place bit corruption passes silently. The default reads a
          random 5% of the pack data on each run, which costs a twentieth of
          the repository in backend reads. Raise the percentage, or use
          `--read-data` to read everything on every run, where reads are cheap.
          An empty list gives the structure-only check.
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
    # Upstream asserts exactly one repository source (repository,
    # repositoryFile or environmentFile). Two checks are added here. A
    # password needs some source, since a missing one fails only at runtime,
    # and a repository URL must not carry credentials into the store.
    assertions = lib.concatLists (lib.mapAttrsToList (name: b: [
        {
          assertion = b.passwordFile != null || b.environmentFile != null;
          message = "othrys.services.restic.backups.${name}.passwordFile is unset and so is environmentFile. Set passwordFile (a secrets-provider path) or supply RESTIC_PASSWORD via environmentFile.";
        }
        {
          assertion = !carriesCredentials b.repository;
          message = "othrys.services.restic.backups.${name}.repository carries credentials in its URL, which would be written to the store. Put the URL in a runtime file and set repositoryFile instead.";
        }
      ])
      cfg.backups);

    # Restic CLI for manual snapshot/restore against the same repositories.
    environment.systemPackages = [pkgs.restic];

    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (name: b:
        lib.nameValuePair "restic-backups-${name}" {
          serviceConfig.ExecStart = lib.mkIf b.runCheck (lib.mkAfter ["${checkStep name b}"]);
          # A failed backup or repository check must reach a human, not die
          # in the journal (cross-module conditional, no hard dependency on
          # notify).
          onFailure = lib.mkIf notifyCfg.enable ["restic-notify-failure@%n.service"];
        })
      cfg.backups)

      # notify-failure@ with a message of its own. The generic unit says that
      # a unit failed, which reads the same for a backup that never ran and
      # for a good backup whose repository check failed. The token is staged
      # the way notify-failure@ stages it.
      (lib.mkIf notifyCfg.enable {
        "restic-notify-failure@" = {
          description = "Failure notification for the restic backup %i.";
          serviceConfig =
            {
              Type = "oneshot";
              ExecStart = "${failureScript} %i";
              DynamicUser = true;
              RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
            }
            // sandbox.baseline
            // lib.optionalAttrs (notifyCfg.tokenFile != null) {
              LoadCredential = ["token:${notifyCfg.tokenFile}"];
            };
        };
      })
    ];

    services.restic.backups =
      lib.mapAttrs (_: b: {
        # The check is the module's own step, see checkStep.
        runCheck = false;
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
